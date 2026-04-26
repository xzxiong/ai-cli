分析日志文件中的性能瓶颈，识别慢操作，提出优化建议，提交 GitHub issue。

Input: $ARGUMENTS (日志文件路径 或 CI URL)

## 输入类型
1. 本地文件：`/path/to/service.log`
2. CI URL：先下载 artifacts 再分析
3. 粘贴内容：保存到临时文件

## 流程

### 1. 获取日志
本地文件直接使用；CI URL 则 `gh run download` 获取 artifacts。

### 2. 提取耗时数据
```bash
# duration=Xs, took Xs, elapsed Xs, cost Xs
grep -n -iE '(duration|took|elapsed|cost|latency|time)[=: ]*[0-9]+(\.[0-9]+)?\s*(s|ms|µs|us|ns|sec|min|m\b)' "$LOG"
# Go test timing
grep -n -E '(--- (PASS|FAIL): .* \([0-9]+\.[0-9]+s\)|^ok\s+\S+\s+[0-9]+\.[0-9]+s)' "$LOG"
# SQL/query timing
grep -n -iE '(query|execute|sql|rows|scan|fetch).*[0-9]+(\.[0-9]+)?\s*(s|ms)' "$LOG"
# Timestamp gap analysis
```

### 3. 识别瓶颈
排序提取的耗时，分类：
- 🔴 Critical: > 60s
- 🟡 Warning: > 10s
- 🟢 Normal: ≤ 10s

分析：Top-20 最慢操作、Stage 级别分解、重复慢模式、时间戳间隙。

### 4. 提出优化建议
| 瓶颈类型 | 优化建议 |
|---------|---------|
| 慢 SQL | 加索引、优化查询、批量操作 |
| 串行 I/O | goroutine 并行化 |
| 重复操作 | 加缓存 |
| 大数据扫描 | 分页、限制结果集 |
| 锁竞争 | 缩小临界区、RWMutex |

### 5. 生成报告
包含：总结表格、Top 瓶颈（位置+上下文+分析+建议+预期提升）、Stage 分解、优化路线图（Quick wins / 中期 / 长期）。

### 6. 提交 Issue
```bash
gh gist create --public --desc "Perf Analysis" <log-files>
gh issue create --repo matrixorigin/matrixflow \
  --title "[PERF]: <bottleneck-summary>" --label "kind/performance" --assignee xzxiong --body "<body>"
gh issue comment <number> --repo matrixorigin/matrixflow --body "<full-report>"
```

Temp files cleaned up after posting.
