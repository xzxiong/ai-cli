---
name: log-perf-analyze
description: |
  Analyze log files for performance bottlenecks, identify slow operations, and propose optimization suggestions. Submits findings as a GitHub issue with log data attached.

  Use this skill when:
  - The user invokes `/log-perf-analyze <log-file-or-ci-url>`
  - The user says "分析耗时" or "analyze perf" followed by a log path or CI URL
  - The user says "log perf" or "性能分析" with a log file or CI URL
  - The user provides log content and asks to analyze performance/latency

  The skill automatically extracts timing data, identifies bottlenecks, proposes optimizations, and submits a GitHub issue.

  **Agent**: Uses `log-perf-agent` with pre-configured shell command permissions.
---

# Log Performance Analysis Skill

## Purpose

Analyze log files to identify performance bottlenecks (slow queries, high-latency operations, long-running stages), propose actionable optimization suggestions, and submit findings as a GitHub issue with log data attached.

## Prerequisites

**Agent**: `log-perf-agent` (`.kiro/agents/log-perf-agent.json`)

**GitHub CLI Scopes**: `repo`, `gist`
```bash
gh auth refresh -s repo -s gist
```

## When Invoked

- `/log-perf-analyze <log-file-path>` — analyze local log file
- `/log-perf-analyze <ci-url>` — download CI artifacts then analyze
- `分析耗时` / `analyze perf` / `log perf` / `性能分析` + log path or CI URL

## Input Types

1. **Local log file**: `/path/to/service.log`
2. **CI URL**: `https://github.com/matrixorigin/matrixflow/actions/runs/<run-id>` — downloads artifacts first
3. **Pasted log content**: User pastes log text directly

## Process

### Step 1: Acquire Log Data

**From local file**:
```bash
WORK_DIR="/tmp/log-perf-$(date +%s)"
mkdir -p "$WORK_DIR"
cp <log-file> "$WORK_DIR/source.log"
```

**From CI URL**:
```bash
WORK_DIR="/tmp/log-perf-<run-id>"
mkdir -p "$WORK_DIR/artifacts"
gh run download <run-id> --repo matrixorigin/matrixflow --dir "$WORK_DIR/artifacts"
# Collect all log files
find "$WORK_DIR/artifacts" -name "*.log" -type f
```

**From pasted content**: Save to `$WORK_DIR/source.log`.

### Step 2: Extract Timing Data

Scan logs for common duration/timing patterns:

```bash
# Pattern 1: duration=Xs, took Xs, elapsed Xs, cost Xs
grep -n -iE '(duration|took|elapsed|cost|latency|time)[=: ]*[0-9]+(\.[0-9]+)?\s*(s|ms|µs|us|ns|sec|min|m\b)' "$LOG_FILE"

# Pattern 2: Go-style timing — "XXX in 3.456s" or "XXX (3.456s)"
grep -n -E '[0-9]+\.[0-9]+s\b' "$LOG_FILE"

# Pattern 3: Timestamps — calculate delta between consecutive log lines
# Format: 2024-01-01T12:00:00 or 2024/01/01 12:00:00 or [12:00:00]
grep -n -E '^\[?[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}[T ]?[0-9]{2}:[0-9]{2}:[0-9]{2}' "$LOG_FILE"

# Pattern 4: SQL/query timing — "query took", "execute in", "rows affected in"
grep -n -iE '(query|execute|sql|rows|scan|fetch).*[0-9]+(\.[0-9]+)?\s*(s|ms)' "$LOG_FILE"

# Pattern 5: Stage/step markers — "step X completed", "phase X done"
grep -n -iE '(step|stage|phase|task|job).*?(complete|done|finish|start)' "$LOG_FILE"

# Pattern 6: Go test timing — "--- PASS: TestXxx (3.45s)", "ok  pkg  3.45s"
grep -n -E '(--- (PASS|FAIL): .* \([0-9]+\.[0-9]+s\)|^ok\s+\S+\s+[0-9]+\.[0-9]+s)' "$LOG_FILE"
```

### Step 3: Identify Bottlenecks

Sort extracted durations and identify:

1. **Top-N slowest operations** (default N=20): Operations exceeding threshold
2. **Threshold classification**:
   - 🔴 Critical: > 60s
   - 🟡 Warning: > 10s
   - 🟢 Normal: ≤ 10s
3. **Stage-level breakdown**: If log has stage markers, compute per-stage duration
4. **Repeated slow patterns**: Same operation appearing slow multiple times
5. **Timestamp gap analysis**: Large gaps between consecutive log lines indicating stalls

```bash
# Extract numeric durations and sort descending
grep -oE '[0-9]+(\.[0-9]+)?\s*(s|ms|min)' "$LOG_FILE" | \
  awk '{
    val=$1; unit=$2;
    if(unit=="ms") val=val/1000;
    if(unit=="min") val=val*60;
    print val, $0
  }' | sort -rn | head -20
```

### Step 4: Analyze & Propose Optimizations

For each bottleneck, analyze context (±10 lines) and propose optimizations:

**Analysis dimensions**:
- What operation is slow (query, I/O, computation, network call)
- Is it repeated (N+1 query problem, retry storms)
- Is it sequential but could be parallel
- Is there unnecessary work (redundant processing, over-fetching)
- Resource contention (lock waits, connection pool exhaustion)

**Common optimization patterns**:
| Bottleneck Type | Optimization Suggestion |
|----------------|------------------------|
| Slow SQL query | Add index, optimize query plan, batch operations |
| Sequential I/O | Parallelize with goroutines/workers |
| Repeated same operation | Add caching layer |
| Large data scan | Add pagination, limit result set |
| Network latency | Connection pooling, keep-alive, reduce round trips |
| Lock contention | Reduce critical section, use RWMutex, lock-free structures |
| Slow test | Mock external deps, reduce test data, parallel subtests |

### Step 5: Generate Report

```markdown
## Performance Analysis Report

**Source**: <log-file-path or ci-url>
**Log Size**: <size> | **Time Span**: <first-timestamp> → <last-timestamp> | **Total Duration**: <Xm Ys>

### Summary

| Metric | Value |
|--------|-------|
| Total operations analyzed | N |
| 🔴 Critical (>60s) | N |
| 🟡 Warning (>10s) | N |
| Total time in slow ops | Xs |

### Top Bottlenecks

#### 1. 🔴 <operation-name> — <duration>
**Location**: <log-file>:L<line-number>
**Context**:
```
<relevant log lines>
```
**Analysis**: <what's happening and why it's slow>
**Optimization**:
- <suggestion-1>
- <suggestion-2>
**Expected improvement**: <estimated speedup>

#### 2. 🟡 <operation-name> — <duration>
...

### Stage Breakdown (if applicable)

| Stage | Duration | % of Total |
|-------|----------|------------|
| <stage-1> | Xs | X% |
| <stage-2> | Xs | X% |

### Optimization Roadmap

**Quick wins** (low effort, high impact):
1. <optimization-1>
2. <optimization-2>

**Medium-term** (moderate effort):
1. <optimization-3>

**Long-term** (architectural changes):
1. <optimization-4>
```

### Step 6: Submit GitHub Issue

Upload log data to Gist, then create issue:

```bash
# Create gist with log data and timing extract
gh gist create --public \
  --desc "Perf Analysis - <source-identifier>" \
  "$WORK_DIR/source.log" \
  "$WORK_DIR/timing-extract.txt"

# Create issue
gh issue create --repo matrixorigin/matrixflow \
  --title "[PERF]: <bottleneck-summary>" \
  --label "kind/performance" \
  --assignee xzxiong \
  --body "<issue-body>"
```

Issue body:
```markdown
**Source**: <log-file or ci-url>
**Analysis Date**: <date>

## Summary
<1-2 sentence summary of key findings>

## Top Bottlenecks
<top 5 bottlenecks with durations>

## Optimization Suggestions
<prioritized list of actionable suggestions>

## Full Logs
<gist-url>

## Additional context
Performance analysis generated from log: <source>
```

### Step 7: Post Detailed Analysis as Comment

```bash
gh issue comment <number> --repo matrixorigin/matrixflow \
  --body "<full-analysis-report>"
```

Post the full report (from Step 5) as a comment, truncated to 60KB if needed.

## Implementation Notes

- **Zero interaction**: Extract everything from input, no confirmation prompts
- **Multi-log support**: If CI artifacts contain multiple logs, analyze each and merge findings
- **Duration normalization**: Convert all durations to seconds for comparison
- **Context preservation**: Always include ±10 lines around each bottleneck for debugging
- **Gist for large logs**: Upload full logs to Gist, keep issue body concise
- **Temp files**: `$WORK_DIR` cleaned up after posting

## Example Flow

```
User: /log-perf-analyze /tmp/ci-issue-23293089386/artifacts/logs/test.log

Kiro: Analyzing log file for performance bottlenecks...
      Log size: 2.3MB | Time span: 12:00:01 → 12:47:33 | Total: 47m32s

      ## Top Bottlenecks

      1. 🔴 TestCatalogIntegration/TestFullSync — 182.3s
         Sequential DB operations in sync loop
         → Suggestion: Batch INSERT, parallelize independent syncs

      2. 🔴 TestMowlEngine/TestLargeDocParse — 95.7s
         Single-threaded PDF parsing
         → Suggestion: Split document into chunks, parallel parse

      3. 🟡 TestWorkerPool/TestConcurrentJobs — 34.2s
         Connection pool exhaustion (max=10, needed=25)
         → Suggestion: Increase pool size or add queue backpressure

      ✅ Issue created: https://github.com/matrixorigin/matrixflow/issues/8700
      ✅ Full analysis posted as comment
      ✅ Logs uploaded to gist: https://gist.github.com/...
```

## Required Shell Commands

- `gh run download <id> --repo matrixorigin/matrixflow` — artifact download
- `gh gist create` — log upload
- `gh issue create --repo matrixorigin/matrixflow` — issue creation
- `gh issue comment --repo matrixorigin/matrixflow` — post analysis
- `gh auth status` / `gh auth refresh` — auth check
- `grep`, `awk`, `sort`, `head`, `tail`, `cat`, `wc`, `find` — log processing
- `mkdir`, `cp`, `rm -rf /tmp/log-perf-*` — temp file management
- `date` — timestamps
