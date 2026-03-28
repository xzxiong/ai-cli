---
name: bvt-analyze
description: |
  Analyze BVT test failures from GitHub Actions CI logs. Extracts error context, identifies patterns, and provides root cause analysis.
  
  Use this skill when:
  - The user says "bvt analyze" followed by a GitHub Actions URL
  - The user invokes `/bvt-analyze <ci-url>`
  - The user provides a GitHub Actions run/job URL and asks to analyze BVT failures
  - The user says "analyze bvt" or "bvt analysis" with a CI URL
---

# BVT Failure Analysis Skill

## Purpose

Analyze BVT test failures by fetching CI logs, extracting error context, and providing detailed root cause analysis.

## When Invoked

User says `bvt analyze <ci-url>` or `/bvt-analyze <ci-url>` with a GitHub Actions run or job URL.

## Process

### Step 1: Extract Run/Job ID

Parse CI URL to extract:
- Run ID from: `https://github.com/*/actions/runs/<run-id>`
- Job ID from: `https://github.com/*/actions/runs/<run-id>/job/<job-id>`

### Step 2: Fetch CI Logs and Artifacts

```bash
# Download artifacts (includes logs as zip)
gh run download <run-id> --repo matrixorigin/matrixflow --dir /tmp/bvt-artifacts-<run-id>

# If artifacts not available, try fetching logs directly
timeout 300 gh run view <run-id> --repo matrixorigin/matrixflow --job <job-id> --log > /tmp/ci-logs-<run-id>.txt

# Fallback to failed logs
timeout 300 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed > /tmp/ci-logs-<run-id>.txt
```

**Artifacts to analyze**:
- Service logs (*.log files)
- Test results
- Coverage reports
- Any uploaded diagnostic files

### Step 3: Extract Error Context

Search for error patterns in both CI logs and artifact files:
- `FAILED` - Test failures
- `ERROR` - Error messages
- `AssertionError` - Assertion failures
- `Exception` - Python exceptions
- `Traceback` - Stack traces
- Test file paths (e.g., `test_*.py::test_*`)

Extract 50 lines before/after each error marker.

**Analyze artifacts**:
```bash
# Search all log files in artifacts
grep -r "ERROR\|FAILED\|Exception\|Traceback" /tmp/bvt-artifacts-<run-id>/ | head -n 100

# Identify critical service logs
find /tmp/bvt-artifacts-<run-id> -name "*.log" -type f
```

### Step 4: Analyze Failures

Identify:
1. **Failed test cases** - Which tests failed
2. **Error types** - Assertion, timeout, exception, etc.
3. **Error messages** - Specific failure reasons
4. **Common patterns** - Recurring issues across multiple failures

### Step 5: Generate Analysis Report

Provide structured analysis:

```markdown
## BVT Failure Analysis

**CI Run**: <run-url>
**Job**: <job-url>
**Status**: <passed/failed>

### Failed Tests

1. **test_name_1**
   - Error: <error-message>
   - Type: <assertion/timeout/exception>
   - Context: <relevant-log-lines>

2. **test_name_2**
   - Error: <error-message>
   - Type: <assertion/timeout/exception>
   - Context: <relevant-log-lines>

### Root Cause Analysis

**Possible Causes:**
- <cause-1>
- <cause-2>
- <cause-3>

**Error Patterns:**
- <pattern-1>
- <pattern-2>

**Suggested Investigation:**
- <suggestion-1>
- <suggestion-2>
- <suggestion-3>

**Related Components:**
- <component-1>
- <component-2>
```

### Step 6: Create BVT Issue

After analysis, automatically create a GitHub issue with log extracts:

1. **Extract failure summary** from analysis
2. **Create archive** of relevant logs:
   ```bash
   # Create zip with critical logs
   cd /tmp/bvt-artifacts-<run-id>
   zip -r /tmp/bvt-issue-<run-id>.zip *.log
   ```
3. **Extract critical log sections** (top errors):
   ```bash
   # Get first 100 lines of critical errors
   grep -r "ERROR\|FAILED" /tmp/bvt-artifacts-<run-id>/ | head -n 100 > /tmp/error-extract-<run-id>.txt
   ```
4. **Submit issue** via `gh issue create` with artifact links
5. **Post analysis** as comment with log extracts

**Issue format**:
```
Title: [MOI BUG]: <first-failed-test> - <error-summary>
Body: <formatted-failure-details>
Labels: kind/bug-moi, kind/bug, bvt-tag-issue
Assignee: xzxiong

Artifacts: 
- CI Artifacts: <ci-artifacts-url>
- Log Archive: Available locally at /tmp/bvt-issue-<run-id>.zip (<size>)
- Download command: gh run download <run-id> --repo matrixorigin/matrixflow
```

**Analysis comment includes**:
- Critical error timeline
- Top 50 error lines from logs
- Root cause analysis
- Investigation steps
- **Artifact download instructions**:
  ```bash
  # Download all artifacts (includes full logs)
  gh run download <run-id> --repo matrixorigin/matrixflow
  
  # Or download specific logs artifact
  gh run download <run-id> --repo matrixorigin/matrixflow --name logs
  ```

**Note**: GitHub doesn't support binary file uploads via CLI. Log archive created locally at `/tmp/bvt-issue-<run-id>.zip`, critical errors extracted to issue comments. Full logs available via CI artifacts.

## Implementation Notes

- **Synchronous execution**: Fetch and analyze in main session
- **Timeout**: 5 minutes for log fetching
- **Artifacts priority**: Download artifacts first (includes logs as zip), fallback to direct log fetch
- **Error handling**: If logs unavailable, report status and suggest manual review
- **Pattern matching**: Use regex to identify common BVT failure patterns
- **Context extraction**: Show relevant log lines around errors
- **Auto-issue creation**: Automatically create GitHub issue after analysis
- **Analysis as comment**: Post detailed analysis as comment to created issue
- **Artifact packaging**: Create zip archive of critical logs for reference
- **Artifact links**: Include CI artifact download links in issue body

## Example Flow

```
User: /bvt-analyze https://github.com/matrixorigin/matrixflow/actions/runs/23044752034/job/66939479337

Claude: Fetching CI logs for job 66939479337...
        
        ## BVT Failure Analysis
        
        **CI Run**: https://github.com/matrixorigin/matrixflow/actions/runs/23044752034
        **Job**: https://github.com/matrixorigin/matrixflow/actions/runs/23044752034/job/66939479337
        **Status**: Failed
        
        ### Failed Tests
        
        1. **test_generic_genai_pipeline**
           - Error: AssertionError - 3 test cases failed
           - Type: Assertion failure
           - Details:
             - 86版式识别YMS_mock_page14.pptx: 作业完成但没有输出文件
             - 页眉页脚_跨页多线表.pdf: 正文表格包含页眉内容
             - test_ppt_title.pdf: 一级标题数量不匹配
        
        ### Root Cause Analysis
        
        **Possible Causes:**
        - PPTX processing pipeline not generating output files
        - PDF header/footer extraction logic failing
        - Title detection algorithm miscounting
        
        **Suggested Investigation:**
        - Check PPTX worker logs
        - Review PDF table extraction logic
        - Verify title detection regex
        
        ---
        
        ✅ Issue created: https://github.com/matrixorigin/matrixflow/issues/8594
        ✅ Analysis posted to issue
```

## Prerequisites

**GitHub CLI Authentication**:
- Requires `repo` and `actions:read` scopes
- Configured in global `~/.kiro/settings.json`

**Shell Commands**:
- `gh run download` - Download artifacts as zip
- `gh run view` - Fetch CI logs
- `grep`, `head`, `tail`, `find` - Log processing
- `timeout` - Timeout control
- `zip` - Create log archives (local storage)
