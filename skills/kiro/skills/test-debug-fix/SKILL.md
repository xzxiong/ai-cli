---
name: test-debug-fix
description: |
  自动化测试-调试-修复迭代循环。运行测试、捕获日志、分析 FAIL 和耗时异常、修复代码、重新验证，最多迭代 5 轮直到全部 PASS。

  Use this skill when:
  - The user says "test debug fix" followed by a test name or command
  - The user invokes `/test-debug-fix <test_name_or_command>`
  - The user says "修复测试" or "跑测试" with a test name
  - The user provides a failing test and asks to fix it iteratively
  - The user says "tdf" followed by a test name or command
---

# Test-Debug-Fix 迭代循环

## Purpose

自动化的测试-调试-修复闭环。Agent 运行测试 → 分析失败 → 修复代码 → 重新验证，最多 5 轮迭代直到全部 PASS。同时分析耗时异常。

## When Invoked

User says `test debug fix <test>`, `/test-debug-fix <test>`, `tdf <test>`, `修复测试 <test>`, or provides a test name/command and asks to fix failures.

## Process

### Step 1: 确定测试命令

根据用户输入和项目类型，构造测试命令:

| 项目类型 | 测试命令模板 | 工作目录 |
|---------|------------|---------|
| moi-core 集成测试 | `go test . -run {TestName} -v -timeout 120s -count=1` | `moi-core/tests` |
| moi-core workers 单元测试 | `go test ./... -run {TestName} -v -timeout 60s -count=1` | `moi-core/workers/go-worker` |
| moi-core catalog 单元测试 | `go test ./... -run {TestName} -v -timeout 60s -count=1` | `moi-core/catalog` |
| moi-core SDK 测试 | `go test ./... -run {TestName} -v -timeout 60s -count=1` | `moi-core/go-sdk` |
| Go 传统服务 | `go test ./... -run {TestName} -v -timeout 60s -count=1` | `{service_dir}` |
| Python 服务 | `poetry run pytest {test_path} -v --tb=long` | `{service_dir}/src` |
| .NET 服务 | `dotnet test --filter {TestName} -v` | `openxml_service` |

### Step 2: 运行测试并捕获日志

测试输出通常非常冗长（尤其是 moi-core 集成测试会启动嵌入式 Catalog 服务器）。必须将输出重定向到文件:

```bash
# 日志文件路径: /tmp/{test_name}_{round}.log
# round 从 1 开始递增

# Go 示例
go test . -run TestXLSXMowl_ParseRealFile_WithYAML -v -timeout 120s -count=1 > /tmp/TestXLSXMowl_ParseRealFile_WithYAML_1.log 2>&1

# Python 示例
poetry run pytest tests/test_workflow.py::test_create -v --tb=long > /tmp/test_create_1.log 2>&1
```

**超时处理**:
- Go 集成测试 (moi-core/tests): 默认 120s，需要运行中的基础设施 (MatrixOne 6001, MinIO, OpenXML 8817)
- Go 单元测试: 默认 60s
- Python: 无特殊超时
- 如果测试超时，在日志中记录并报告给用户，建议检查基础设施状态 (`make status`)

### Step 3: 分析日志文件

#### 3.1 提取 FAIL 信息

```bash
# 快速检查是否有失败
grep -E "^--- FAIL|FAIL\s+|Error Trace:|Error:|panic:" /tmp/{test_name}_{round}.log

# 提取完整的失败上下文 (Go test)
grep -B 5 -A 20 "--- FAIL" /tmp/{test_name}_{round}.log

# 提取 panic 堆栈
grep -A 30 "panic:" /tmp/{test_name}_{round}.log

# Python pytest 失败提取
grep -B 2 -A 20 "FAILED\|AssertionError\|Error" /tmp/{test_name}_{round}.log
```

#### 3.2 分类失败类型

| 失败类型 | 特征 | 处理策略 |
|---------|------|---------|
| 断言失败 (Assertion) | `Not equal`, `expected:`, `actual:` | 分析期望值 vs 实际值，定位业务逻辑 bug |
| 编译错误 (Compile) | `cannot find package`, `undefined:`, `syntax error` | 修复导入、语法、类型错误 |
| 运行时 panic | `panic:`, `runtime error:` | 分析堆栈，修复空指针/越界等 |
| 超时 (Timeout) | `test timed out`, `context deadline exceeded` | 检查基础设施连接、增加超时、优化逻辑 |
| 连接错误 | `connection refused`, `dial tcp` | 提示用户检查基础设施 (MO/MinIO/OpenXML)，停止迭代 |
| 数据不一致 | 字段值为空或不匹配 | 追踪数据流，定位赋值缺失 |

#### 3.3 输出分析报告

对每个 FAIL case:

```
FAIL Case #{N}: {测试函数名}
  类型: {断言失败 / 编译错误 / panic / 超时 / 连接错误}
  位置: {文件:行号}
  期望: {expected value}
  实际: {actual value}
  根因分析: {简要分析}
  修复方案: {具体修复步骤}
```

### Step 4: 耗时异常分析

即使测试 PASS，也应检查耗时异常。耗时异常往往预示潜在问题。

#### 4.1 提取耗时数据

```bash
# Go test: 总耗时
grep -E "^(ok|FAIL)\s+\S+\s+[\d.]+s" /tmp/{test_name}_{round}.log

# Go test: 每个子测试耗时
grep -E "^--- (PASS|FAIL|SKIP): \S+ \([\d.]+s\)" /tmp/{test_name}_{round}.log

# Go test: HTTP 请求耗时 (Catalog 嵌入式服务器日志)
grep '"duration"' /tmp/{test_name}_{round}.log | awk -F'"duration":' '{print $2}' | tr -d '},' | sort -rn | head -20
```

#### 4.2 耗时基准与告警阈值

| 测试类型 | 正常范围 | 告警阈值 | 严重阈值 |
|---------|---------|---------|---------|
| moi-core 集成测试 (含嵌入式 Catalog 启动) | 30-60s | >90s | >120s (接近超时) |
| moi-core 集成测试 (单个工作流执行) | 0.5-5s | >10s | >30s |
| Go 单元测试 | <5s | >15s | >30s |
| Python pytest (单个 case) | <10s | >30s | >60s |
| 单个 HTTP 请求 (Catalog API) | <0.1s | >1s | >5s |
| 嵌入式 Catalog 启动 | 15-30s | >45s | >60s |

#### 4.3 耗时异常分类

| 异常类型 | 特征 | 可能原因 | 处理策略 |
|---------|------|---------|---------|
| 启动慢 | Catalog 嵌入式服务器启动 >45s | MO 数据库连接慢、schema 初始化慢 | 检查 MO 状态，考虑连接池预热 |
| 请求慢 | 单个 API 请求 duration >1s | 数据库查询慢、锁竞争、网络延迟 | 分析慢请求的 trace_id |
| 工作流执行慢 | 工作流从提交到完成 >10s | Worker 处理慢、外部服务响应慢 | 检查 Worker 日志、外部服务健康状态 |
| 整体超时边缘 | 总耗时 >90s (120s 超时) | 多个慢步骤累积 | 逐步骤分析，找出最慢环节 |
| 跨轮次劣化 | 本轮比上轮慢 >50% | 代码修改引入性能回归 | 对比两轮日志，定位劣化点 |

#### 4.4 耗时分析报告格式

```
耗时分析:
  总耗时: {X}s (基准: {Y}s, 状态: 正常/告警/严重)
  嵌入式 Catalog 启动: {X}s
  工作流执行: {X}s
  最慢 HTTP 请求: {endpoint} {X}s (trace_id: {id})
  跨轮次对比: 第{N}轮 {X}s → 第{N+1}轮 {Y}s ({+/-Z%})
  建议: {无 / 检查 MO 状态 / 优化查询 / 增加超时}
```

#### 4.5 耗时异常处理决策

- 告警级别: 在报告中标注，不阻塞修复流程，但提醒用户关注
- 严重级别: 在报告中高亮，建议用户先排查基础设施再继续
- 跨轮次劣化: 如果修复代码后耗时劣化 >50%，回滚修改并重新分析

### Step 5: 修复代码

#### 5.1 修复原则

1. **最小改动原则**: 只修改导致测试失败的代码，不做无关重构
2. **保持一致性**: 修复后的代码风格与周围代码一致
3. **不破坏其他测试**: 修复一个 case 不应导致其他 case 失败
4. **静态检查**: 修复后运行 `go vet` (Go) 或 `ruff check` (Python) 确认无新警告

#### 5.2 修复流程

1. 读取失败相关的源代码文件
2. 定位问题代码段
3. 应用修复
4. 如果是 Go 代码，运行 `go vet` 检查
5. 记录修改内容

#### 5.3 常见修复模式

| 问题模式 | 修复方式 |
|---------|---------|
| 元数据字段为空 | 在数据加载阶段补充字段解析 |
| 类型断言失败 | 添加类型检查或使用安全断言 |
| 空指针 | 添加 nil 检查 |
| JSON 序列化问题 | 检查 struct tag、omitempty、字段类型 |
| 并发竞争 | 添加锁或使用 channel |
| 外部服务调用失败 | 检查 URL、超时、请求格式 |

### Step 6: 重新验证

使用与 Step 2 相同的测试命令，递增 round 编号:

```bash
go test . -run {TestName} -v -timeout 120s -count=1 > /tmp/{test_name}_{round+1}.log 2>&1
```

**判断结果**:
- 全部 PASS → 输出成功报告，流程结束
- 仍有 FAIL → 回到 Step 3 继续分析，递增迭代计数
- 新增 FAIL (之前没有的) → 回滚上一轮修改，重新分析

**迭代终止条件**:
- 所有测试 PASS
- 达到最大迭代次数 (5 轮)
- 遇到基础设施问题 (连接错误等，需要用户介入)
- 遇到无法自动修复的问题 (需要架构变更等)

### Step 7: 最终报告

迭代结束后，输出简洁总结:

```
测试修复完成:
- 迭代轮数: {N}
- 修改文件: {file1}, {file2}, ...
- 修复的 FAIL case: {list}
- 剩余未修复 (如有): {list + 原因}
- 耗时趋势: 第1轮 {X}s → 第{N}轮 {Y}s
- 耗时告警 (如有): {慢请求/启动慢/劣化 等}
```

## moi-core 特殊注意事项

### 多模块结构

moi-core 是多模块 Go 项目，不同测试在不同模块下运行:

| 测试类型 | go.mod 位置 | 工作目录 |
|---------|------------|---------|
| 集成测试 | `moi-core/tests/go.mod` | `moi-core/tests` |
| Worker 单元测试 | `moi-core/workers/go-worker/go.mod` | `moi-core/workers/go-worker` |
| Catalog 单元测试 | `moi-core/catalog/go.mod` | `moi-core/catalog` |
| SDK 测试 | `moi-core/go-sdk/go.mod` | `moi-core/go-sdk` |

### 集成测试依赖

moi-core 集成测试会启动嵌入式 Catalog 服务器，需要:
- MatrixOne 数据库 (端口 6001)
- MinIO 对象存储 (端口 9100/9101)
- OpenXML 服务 (端口 8817) — 部分测试需要
- RocketMQ (端口 8080-8082) — 部分测试需要

如果测试因连接失败而报错，提示用户运行 `make status` 检查基础设施状态。

### Go 版本约束

必须使用 Go 1.24.x。Go 1.25+ 会导致 bytedance/sonic 编译失败。

### 静态检查标准

- moi-core: `go vet` + `staticcheck` 零警告，不使用 `nolint` 指令
- 传统 Go 服务: `gofmt` + `golangci-lint`
- Python: `ruff check`

## Implementation Notes

- **日志重定向**: 所有测试输出必须重定向到 `/tmp/{test_name}_{round}.log`，避免输出过长
- **最大迭代**: 5 轮，超过则停止并报告剩余问题
- **回滚机制**: 如果修复引入新 FAIL，回滚上一轮修改
- **基础设施检查**: 连接错误时停止迭代，提示用户检查
- **耗时跟踪**: 每轮记录耗时，检测跨轮次劣化

## Example Flow

```
User: tdf TestXLSXMowl_ParseRealFile_WithYAML

Agent: 开始 Test-Debug-Fix 循环...

        第 1 轮:
        运行: go test . -run TestXLSXMowl_ParseRealFile_WithYAML -v -timeout 120s -count=1
        日志: /tmp/TestXLSXMowl_ParseRealFile_WithYAML_1.log

        FAIL Case #1: TestXLSXMowl_ParseRealFile_WithYAML/sheet_metadata
          类型: 断言失败
          位置: xlsx_mowl_test.go:156
          期望: "Sheet1"
          实际: ""
          根因: ParseSheetMetadata 未从 Catalog API 获取 sheet name
          修复: 在 parseXLSX() 中添加 sheet name 字段赋值

        耗时分析:
          总耗时: 45s (基准: 30-60s, 状态: 正常)

        修复中... 修改 xlsx_parser.go:89

        第 2 轮:
        运行: go test . -run TestXLSXMowl_ParseRealFile_WithYAML -v -timeout 120s -count=1
        日志: /tmp/TestXLSXMowl_ParseRealFile_WithYAML_2.log

        全部 PASS ✅

        测试修复完成:
        - 迭代轮数: 2
        - 修改文件: xlsx_parser.go
        - 修复的 FAIL case: sheet_metadata
        - 耗时趋势: 第1轮 45s → 第2轮 43s
```

## Prerequisites

- Go 1.24.x (moi-core, Go 服务)
- Python 3.11~3.12 + Poetry (Python 服务)
- .NET SDK 8.0 (openxml_service)
- 基础设施运行中 (根据测试类型): MatrixOne, MinIO, OpenXML, RocketMQ
