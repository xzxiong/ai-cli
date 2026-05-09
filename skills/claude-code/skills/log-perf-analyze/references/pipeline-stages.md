# V2 Pipeline Stage Reference

## Log Pattern → Stage Mapping

This document maps log patterns to pipeline stages for automated parsing.

## Duration Metrics (from `byoa.metrics.decorators`)

These are the operation names logged by the metrics decorators, along with the pipeline stage they belong to:

```
operation                       → Stage
─────────────────────────────── ─────────────────────────────────
convert_office_format           → 1. File Conversion
preprocess_with_paddle          → 2. Paddle Preprocessing
send_mineru_request             → 3a. MinerU API Call
parse_pdf_mineru                → 3b. MinerU Full Parse
extract_response_files          → 3c. MinerU Response Extract
mineru_parse                    → 3d. MinerU Block Parse
create_table_blocks             → 4. Block Creation
vlm_call (FlowchartTable*)      → 5. Flowchart Detection
l1_html_generation              → 6. L1 HTML Generation
cross_page_table_merge          → 8. CrossPage Table Merge
extract_structures              → 8a. CrossPage Structure Extract
validate_candidates             → 8b. CrossPage Candidate Validation
image_fragment_merge            → 9. ImageFragment Merge
header_footer_remove            → 10. Header/Footer Removal
detect_header_footer            → 10a. Header/Footer Detection (VLM)
title_detect_batch              → 11. Title Detection
content_process                 → 12a. Content Processing
table_process                   → 12b. Table Processing
s3_upload_v2_resource           → (debug upload, ignore for timing)
```

## VLM Call Categories

VLM calls are logged with a tag in brackets. Map them to stages:

| VLM Tag | Stage | Description |
|---------|-------|-------------|
| `[l1_html_generation]` | 6 | 单页表格 HTML 生成 |
| `[cross_page_table_html_gen]` | 8a | 跨页表结构提取 HTML 生成 |
| `[cross_page_table_match]` | 8b | 跨页表候选匹配验证 |
| `[FlowchartTableDetection]` | 5 | 流程图表格检测 |
| `[ImageFragmentMerger]` | 9 | 图片碎片合并判断 |
| `[HeaderFooterDetector]` | 10a | 页眉页脚检测 |
| `[TitleDetector]` | 11 | 标题层级检测 |

## Key Log Patterns for Stage Boundaries

```
# Stage start/end markers
"Running component DOCXToDocument"          → Stage 1 start
"Using V2 pipeline for DOCX processing"     → Stage 1 V2 path
"Preprocessing complete: N tables detected"  → Stage 2 end
"Using V2 pipeline for file_id="            → Stage 3 end / V2 start
"Parsed N blocks from MinerU"              → Stage 4 start
"Flowchart predetect: checking N"           → Stage 5 start
"Flowchart predetect complete:"             → Stage 5 end
"L1: Generating HTML for N table blocks"    → Stage 6 start
"L1: HTML generation complete: M/N"         → Stage 6 end
"Placeholder replacement complete:"          → Stage 7 end
"CrossPageMerger.*Found N candidate pairs"  → Stage 8 start
"Merge complete: N → M tables"             → Stage 8 end
"Image fragment merge done:"                → Stage 9 end
"Header/footer removal done:"              → Stage 10 end
"Batch detection completed:"               → Stage 11 end
"Dispatcher.*Final result:"                 → Stage 12 end
"pipeline.run result:"                      → Pipeline complete
"Successfully created file"                 → Job complete
```

## VLM Slow Call Warning Format

```
[<tag>] Slow VLM call: total=<X>s, model_duration=<Y>s, ttft=<Z>s, input_tokens=<N>, output_tokens=<M>
```

- `total`: 总耗时（含网络）
- `model_duration`: 模型推理耗时
- `ttft`: Time to First Token
- If `total ≈ model_duration`: 瓶颈在模型推理
- If `total >> model_duration`: 瓶颈在网络/排队

## VLM Timeout Format

```
[<tag>] VLM call exceeded total timeout (<N>s, actual=<M>s), aborting
```

默认超时通常为 303s（job-consumer 侧）或 300s（llm-proxy Client.Timeout）。

## llm-proxy Error Patterns

### Client Timeout (configurable, default 30s, IDC typically 300s)
```json
{"level":"error", "msg":"Chat completion failed", "error":"...context deadline exceeded (Client.Timeout exceeded while awaiting headers)"}
```
原因：上游 API（DashScope/vLLM）未在 `config.Timeout` 内返回响应头。

**超时配置链**:
- `llm-proxy/pkg/models/types.go:468` → `Backend.Timeout` (per-backend)
- `llm-proxy/pkg/config/config.go:295-296` → 默认 30s
- `llm-proxy/pkg/adapter/qianwen.go:87` → `http.Client{Timeout: config.Timeout}`
- IDC 实际配置通常为 300s（通过 DB 动态配置）

### DashScope 限流 (503)
```json
{"level":"error", "msg":"Chat completion failed", "error":"OpenAI API error: <503> InternalError.Algo.ModelServingError.ServiceUnavailable: Too many requests..."}
```
原因：DashScope API 并发/TPM 限额被打满。

### Error Chain Pattern (已确认)
高并发重请求 → DashScope 排队/变慢 → tok/s 退化 5x → 请求超 300s 超时 → 重试请求打到已过载的 DashScope → 503 限流 → 恶性循环

## Output Speed Benchmarks

基于实际观测的 VLM 输出速率参考值（qwen3.5-27b via DashScope）：

| 并发情况 | Output Speed | 说明 |
|---------|-------------|------|
| 低并发（1~2 请求） | 60~80 tok/s | 正常速率 |
| 中并发（3~5 请求） | 25~40 tok/s | 性能下降 |
| 高并发（>5 请求） | 12~15 tok/s | 严重退化，接近超时 |

当 output_tokens > 5000 且速率 < 20 tok/s 时，大概率会超时。

## Dual Metric System

V2 Pipeline 存在两套并行的 metric 系统：

| 系统 | 记录方式 | 用途 | 查看方式 |
|------|---------|------|---------|
| **Prometheus** | `@track_function_latency_metrics(operation="X")` | Grafana Dashboard | `function_duration_seconds{operation="X"}` |
| **PerformanceProfiler** | `with self._track("Y"):` | 性能 Profile 报告 | 日志中的 `[Performance]` 段 |

**常见名称不一致**:

| Prometheus operation | Profiler stage | 实际范围 |
|---------------------|---------------|---------|
| `l1_html_generation` | `table_html_generation` | `_generate_html_for_all_tables()` wall-clock |
| `cross_page_table_merge` | `cross_page_table_merge` | `merge()` wall-clock |
| `detect_header_footer` | `header_footer_detection` | VLM 页眉页脚检测 |

**Prometheus Histogram 分桶** (`workflow_be/src/byoa/metrics/constant.py`):
```
[0.1, 0.5, 1, 2, 5, 10, 20, 30, 45, 60, 90, 120, 180, 300, 600, 1200, 1800, 2700, 3600]
```

关键稀疏区间：120→180→300→600。实际值 303s 落入 (300, 600] 桶，p95 插值可能被拉高到 ~570s (9.5min)。

## llm-proxy Timeout Configuration

| 层级 | 配置位置 | 默认值 | 说明 |
|------|---------|--------|------|
| Backend HTTP Client | `llm-proxy/pkg/adapter/qianwen.go:87` | `config.Timeout` | per-backend 配置 |
| Backend Timeout 默认 | `llm-proxy/pkg/config/config.go:296` | 30s | 未配置时的 fallback |
| Health Check | `*/adapter/*.go` (各 adapter) | 5s | 健康检查专用 |
| Management Client | `llm-proxy/cmd/management/commands/context.go:37` | 30s | CLI 管理工具 |
| Server Read/Write | `llm-proxy/pkg/config/config.go:200-201` | 30s/30s | HTTP server 超时 |

IDC 环境 DashScope backend 通常配置为 300s（通过 DB 动态加载，非 YAML 文件）。
