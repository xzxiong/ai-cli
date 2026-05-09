---
name: log-perf-analyze
description: "分析日志文件中的性能瓶颈，识别慢操作，提出优化建议，提交 GitHub issue。Use this skill when the user mentions: analyzing parsing performance, slow document parsing, job-consumer performance, VLM/LLM call latency, llm-proxy analysis, pipeline stage timing, table HTML generation slowness, cross-page table merge performance, or any document processing workflow bottleneck in IDC/dev/qa/prod environments. Also trigger when the user asks to analyze logs from byoa, job-consumer, llm-proxy, or references file_id/job_id for performance investigation."
---

# Log Performance Analyzer

You are a performance engineer for the MOI platform's document parsing pipeline. Your job is to trace a document's processing lifecycle across job-consumer and llm-proxy, compute per-stage timing, identify bottlenecks, and produce a structured analysis report.

## Key Lessons (from past analyses)

1. **Two metric systems exist**: `@track_function_latency_metrics` → Prometheus histogram (Grafana); `self._track()` → PerformanceProfiler (profile report). They may use different names for the same operation (e.g., `l1_html_generation` vs `table_html_generation`).
2. **Prometheus p95 can be misleading**: Histogram bucket interpolation between sparse buckets (e.g., 300→600) exaggerates the percentile. Always check bucket boundaries in `constant.py`.
3. **DashScope tok/s degrades 5-6x under concurrent heavy requests**: Normal=60-80 tok/s, degraded=12-15 tok/s. This is the #1 root cause of VLM timeouts, not model capability.
4. **Two-round L1 HTML mechanism doubles timeout**: Round 1 timeout (303s) + Round 2 retry on same overloaded API (303s) = 606s wall-clock.
5. **Token estimation error in ratelimiter**: Overestimates by ~10x on average but underestimates 3x on the heaviest requests — the exact ones that need throttling.

## Architecture Overview

The document parsing pipeline involves these components:

```
User Upload → moi-backend → job queue → job-consumer (Python, byoa)
                                              │
                                              ├─ DOCX/PPTX → WPS convert → PDF
                                              ├─ Paddle preprocessing (table detection + whitening)
                                              ├─ MinerU parsing (layout extraction)
                                              └─ V2 Pipeline ──┬─ FlowchartTableDetection (VLM)
                                                                ├─ L1 HTML Generation (VLM) ← 主要瓶颈
                                                                ├─ CrossPage Table Merge (VLM)
                                                                ├─ ImageFragment Merge (VLM)
                                                                ├─ Header/Footer Removal
                                                                ├─ Title Detection (VLM, Stage0/1/2)
                                                                ├─ Content Dispatch (table/text processing)
                                                                └─ DocumentWriter (写入 DB)
                                              │
                              VLM calls ──→ llm-proxy ──→ DashScope / local vLLM
```

### Key Components

| Component | Pod Pattern | Namespace | Role |
|-----------|-------------|-----------|------|
| job-consumer | `chart-byoa-job-consumer-*` | `mo-pl` (IDC) / `moi-*` | 文档解析主进程，运行 V2 Pipeline |
| llm-proxy | `chart-llm-proxy-*` | `mo-pl` / `moi-*` | VLM/LLM 请求代理，转发到 DashScope 或本地模型 |
| MinerU | `chart-mineru-*` / API | - | PDF 布局解析 |
| PaddleOCR | 内嵌或外部 API | - | 表格区域检测 |

### V2 Pipeline Stages (按执行顺序)

| # | Stage | Log Keyword | VLM? | 典型耗时 |
|---|-------|------------|------|---------|
| 1 | 文件格式转换 | `convert_office_format` | No | 1~5s |
| 2 | Paddle 预处理 | `preprocess_with_paddle` | No | 30~60s |
| 3 | MinerU 解析 | `parse_pdf_mineru`, `send_mineru_request` | No | 10~30s |
| 4 | Block 创建 | `create_table_blocks`, `_do_process.*Parsed.*blocks` | No | <1s |
| 5 | 流程图表格检测 | `FlowchartTableDetection`, `flowchart_detector` | Yes | 5~20s/表 |
| 6 | **L1 HTML Generation** | `l1_html_generation`, `_generate_html_for_all_tables` | **Yes** | **60~303s** |
| 7 | Placeholder 替换 | `_replace_placeholders_with_tables` | No | <1s |
| 8 | **CrossPage Table Merge** | `cross_page_table_merge`, `cross_page_table_html_gen` | **Yes** | **60~300s** |
| 9 | ImageFragment Merge | `image_fragment_merge`, `ImageFragmentMerger` | Yes | 5~15s |
| 10 | Header/Footer 去除 | `header_footer_remove`, `HeaderFooterRemover` | Opt | <1s~10s |
| 11 | Title Detection | `title_detect_batch`, `TitleDetector` | Yes | 40~120s |
| 12 | Content Dispatch | `content_process`, `table_process`, `Dispatcher.*Final` | Opt | 30~60s |
| 13 | DocumentWriter | `documents_written`, `pipeline.run result` | No | <5s |

**Stage 6 (L1 HTML Gen) 和 Stage 8 (CrossPage Merge) 是最常见的瓶颈，通常占总耗时 60~80%。**

## Workflow

### Step 1: Identify Target

从用户提供的信息中提取：
- **file_id** 或 **job_id** — 唯一标识处理任务
- **时间范围** — 大概的处理时间窗口
- **环境** — IDC / dev / qa / prod

如果用户提供了 GitHub issue URL，先用 `gh issue view` 获取详情，从 issue body/comments 中提取 file_id、job_id、时间范围。

### Step 2: Locate Processing Pod

在对应环境的 job-consumer pods 中搜索 file_id：

```bash
# 列出所有 job-consumer pods
KUBECONFIG=~/.kube/<config> kubectl get pods -n <namespace> | grep job-consumer

# 在每个 pod 中搜索 file_id
for pod in <pod-list>; do
  echo "=== $pod ==="
  KUBECONFIG=~/.kube/<config> kubectl logs -n <namespace> "$pod" --since=24h 2>&1 | grep -c "<file_id>"
done
```

### Step 3: Extract Pipeline Logs

找到处理 pod 后，提取完整处理日志：

```bash
# 提取从开始到结束的完整日志
KUBECONFIG=~/.kube/<config> kubectl logs -n <namespace> <pod> --since=24h 2>&1 \
  | sed -n '/target file <file_id>/,/No pending file found/p' > /tmp/<file_id>.log

# 去除 ANSI 颜色码
sed -i 's/\x1b\[[0-9;]*m//g' /tmp/<file_id>.log
```

### Step 4: Parse Stage Timings

从日志中提取每个阶段的耗时。关键 duration 指标（由 `byoa.metrics.decorators` 记录）：

```
convert_office_format          → DOCX/PPTX 转 PDF
preprocess_with_paddle         → Paddle 表格检测
send_mineru_request            → MinerU API 调用
parse_pdf_mineru               → MinerU 完整解析
l1_html_generation             → L1 表格 HTML 生成（VLM）
cross_page_table_merge         → 跨页表合并
extract_structures             → 跨页表结构提取（VLM）
validate_candidates            → 跨页表候选验证
image_fragment_merge           → 图片碎片合并
header_footer_remove           → 页眉页脚去除
title_detect_batch             → 标题检测
content_process                → 内容处理
table_process                  → 表格处理
```

关注以下关键日志模式：

```bash
# VLM 慢调用 (WARNING 级别)
grep "Slow VLM call" /tmp/<file_id>.log

# VLM 超时
grep "VLM call exceeded total timeout" /tmp/<file_id>.log

# L1 HTML 生成结果
grep "_generate_html_for_all_tables.*complete" /tmp/<file_id>.log

# CrossPage 合并结果  
grep "Merge complete" /tmp/<file_id>.log

# Pipeline 最终结果
grep "Final result" /tmp/<file_id>.log
```

### Step 5: Correlate with llm-proxy

从 llm-proxy 提取同时段的日志，关联 VLM 调用：

```bash
# 提取 llm-proxy 日志（排除 health check）
KUBECONFIG=~/.kube/<config> kubectl logs -n <namespace> <llm-proxy-pod> --since=24h 2>&1 \
  | grep -v '/health' \
  | grep '<time-window>' > /tmp/llm-proxy.log
```

llm-proxy 日志是 JSON 格式，关键字段：

| 字段 | 说明 |
|------|------|
| `status` | HTTP 状态码。200=成功，500=失败 |
| `duration` | 请求耗时（秒） |
| `model` | 模型名称（如 `qwen3.5-27b`） |
| `backend` | 后端名称 |
| `endpoint` | 上游 API 地址（DashScope / local vLLM） |
| `prompt_tokens` | 输入 token 数 |
| `completion_tokens` | 输出 token 数 |
| `remote_addr` | 请求来源 IP（映射到 job-consumer pod） |

关键分析维度：

1. **请求统计**：总请求数、成功/失败数、按分钟聚合
2. **500 错误分类与因果链**：
   - `context deadline exceeded` / `Client.Timeout` → llm-proxy 硬超时（默认 300s，后端配置 `config.Timeout`）
   - `Too many requests` / 503 → 上游 API 限流（DashScope `InternalError.Algo.ModelServingError.ServiceUnavailable`）
   - **因果链分析**：是否 "高并发 → API 限流 → 超时 → 重试 → 更多限流" 的恶性循环？
3. **慢调用 (>60s)**：列出耗时、token 数、输出速率 (tok/s)
4. **输出速率** (`completion_tokens / duration`)：反映模型推理性能和并发压力
   - 基准：低并发 60-80 tok/s，高并发可退化到 12-15 tok/s
5. **来源分布**：`remote_addr` 映射到 pod IP，判断是否多 pod 并发竞争
6. **Token 预估准确性**：对比 ratelimiter 预估 vs 实际 token，评估限流器有效性

```bash
# 映射 IP 到 pod
KUBECONFIG=~/.kube/<config> kubectl get pods -n <namespace> -o wide | grep job-consumer
```

### Step 5b: Metric Code Tracing (当 Grafana 指标异常时)

当需要解释 Grafana dashboard 上的异常指标时，**必须追溯到代码级别**：

1. **定位 Prometheus metric 记录点**:
   ```bash
   # 在 workflow_be 中搜索 metric operation name
   grep -rn "<operation_name>" workflow_be/src/byoa/metrics/
   grep -rn "<operation_name>" workflow_be/src/byoa/integrations/document_parser/v2/
   ```

2. **区分两套 metric 系统**:
   - `@track_function_latency_metrics(operation="X")` → Prometheus `function_duration_seconds{operation="X"}` → **这是 Grafana 展示的**
   - `with self._track("Y"):` → PerformanceProfiler 内部计时 → 性能报告用，非 Grafana
   - 注意：X 和 Y 可能不同名！如 `l1_html_generation`(Prometheus) vs `table_html_generation`(Profiler)

3. **分析 histogram bucket 精度**:
   ```python
   # workflow_be/src/byoa/metrics/constant.py
   default_duration_bucket = [0.1, 0.5, 1, 2, 5, 10, 20, 30, 45, 60, 90, 120, 180, 300, 600, ...]
   ```
   如果实际值落在稀疏桶区间（如 303s 落入 300→600），Prometheus 线性插值会严重偏差。

4. **确认 metric 记录范围**:
   - 是单次 VLM 调用的耗时？还是整个函数（含并发 + 等待所有 future）的 wall-clock？
   - 是否包含重试？（`_generate_html_for_all_tables` 被调两次，各自独立记录）
   - 是否包含超时等待？（ThreadPoolExecutor `future.result(timeout=...)` 的 wall-clock）

5. **检查 Grafana Dashboard 定义**:
   ```bash
   grep -n "<operation>" catalog_service/pkg/metrics/dashboard/dashboard_job_consumer.go
   ```

### Step 5c: Cross-Document Comparison (当有多个对比样本时)

如果同一文档以不同格式处理（如 DOCX vs PDF），或同一文档在不同环境处理，进行对比分析：

| 对比维度 | 关注点 |
|---------|--------|
| **Pipeline 差异** | 哪些阶段是共享的？哪些是格式特有的？ |
| **VLM 调用对比** | 同一表格在两种路径下的 tok/s、超时率 |
| **时间重叠** | 两个任务是否同时处理？是否存在资源竞争？ |
| **性能差异根因** | 是格式差异、还是并发竞争、还是时序偶然？ |

关键：如果两个任务不重叠（如 DOCX 完成后 PDF 才开始），tok/s 差异反映的是 **API 负载变化**而非格式差异。

### Step 6: Parallel Agent Strategy

对于多日志文件分析，**使用 Agent 工具并行分析**：

```python
# 同时启动 3 个独立分析 agent
Agent("job-consumer log", prompt="分析 /tmp/docx.log: VLM 调用明细、阶段耗时、超时模式...")
Agent("llm-proxy log", prompt="分析 /tmp/llm-proxy.log: 请求分布、错误分类、tok/s、并发影响...")
Agent("comparison log", prompt="分析 /tmp/pdf.log 并与 DOCX 处理对比...")
```

每个 agent 的 prompt 必须自包含：
- 明确要分析的文件路径
- 列出需要回答的具体问题
- 要求精确的数字和时间戳（不要模糊描述）

**Agent 返回后，自己做跨日志关联**：
- job-consumer 的 VLM 超时时间 ↔ llm-proxy 的 500 错误时间
- job-consumer 的 file_id ↔ llm-proxy 的 remote_addr（需 pod IP 映射）
- 多 pod 并发窗口 ↔ DashScope tok/s 退化曲线

### Step 7: Generate Analysis Report

生成结构化的 Markdown 分析报告，包含：

```markdown
# <标题>

> 关联 Issue: [repo#number](url)

## 现象
<简述问题：什么文档、什么环境、耗时多长>

## 基本信息
- file_id / job_id
- 处理 Pod
- 时间范围

## 处理流水线各阶段耗时

| # | 阶段 | 时间范围 | 耗时 | 占比 | 说明 |
|---|------|---------|------|------|------|
...

## 耗时分布（可视化）
用 ASCII 条形图展示各阶段占比

## VLM 调用详情
### L1 HTML Generation
逐个表格列出：VLM 耗时、input_tokens、output_tokens、状态

### CrossPage Table Merge  
逐步骤列出耗时

## llm-proxy 关联分析
### 请求统计
### 500 错误分类与因果链
### VLM 输出速率分析（按时间段 + 按并发度）
### 请求来源分布
### Token 预估准确性

## Metric 代码追溯（如果涉及 Grafana 指标异常）
### 指标记录机制
### Histogram 分桶分析
### Grafana 展示值 vs 实际值

## 根因分析
### 直接原因
### 链路问题（因果链）
### 影响范围

## 建议
### 短期（P0, 本周）
### 中期（P1, 1-2周）
### 长期（P2）

## 附：完整处理时间线
ASCII 时间线，标注瓶颈点和 VLM tok/s 变化
```

### Step 8: Save and Publish

1. **保存分析文档**到 `docs/issue/` 或 `docs/analysis/`（视所在 repo 而定），命名 `YYYYMMDD-<描述>.md`
2. **上传日志**到 Gist（去除 ANSI 颜色码），在分析文档和 issue comment 中引用 Gist URL
3. **发布到 Issue Comment**：如果是从 issue-analyzer 调用的，发布摘要版到 issue；如果是独立分析，询问用户是否需要发布

## Environment Map

| Environment | KUBECONFIG | Namespace |
|-------------|-----------|-----------|
| IDC | `~/.kube/idc-unit` | `mo-pl` |
| dev | `~/.kube/ack-unit-hz-new` | `moi-*` |
| qa | `~/.kube/ack-unit-hz-qa` | `moi-*` |
| prod | `~/.kube/ack-prod-unit-hz` | `moi-*` |

## Important Rules

1. 日志中时间戳通常是 UTC，issue 中用户报告的时间通常是 CST (UTC+8)，注意转换
2. ANSI 颜色码在上传/展示前必须去除
3. 敏感信息（API Key、Token）需脱敏
4. 分析文档命名遵循 `YYYYMMDD-<描述>.md` 规范
5. Issue comment 中引用本仓库文档使用完整 GitHub URL
