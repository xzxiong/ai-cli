---
name: bvt-issue
description: |
  Zero-interaction GitHub issue submission for BVT bugs. Extracts all information from user's initial message.
  
  Use this skill when:
  - The user invokes `/bvt-issue <bug description>`
  - The user says "new bvt issue" followed by bug details
  - The user provides BVT bug details directly
  - The user asks to re-analyze an existing issue (e.g., "reanalyze #8593", "re-analyze https://github.com/.../issues/8593")
  
  The skill automatically extracts test name, creates title, and submits the issue without additional prompts.
  
  **Agent**: Uses `bvt-issue-agent` with pre-configured shell command permissions.
---

# BVT Issue Submission Skill

## Purpose

Submit BVT bugs to GitHub instantly by extracting all information from the user's initial message.

## Prerequisites

**Agent Configuration**:
The skill uses `bvt-issue-agent` (`.kiro/agents/bvt-issue-agent.json`) with pre-configured shell command permissions:
- `gh` commands (auth, issue, run, api, gist) - Auto-approved
- Log processing (`grep`, `head`, `tail`, `cat`, `jq`) - Auto-approved
- Cleanup (`rm -rf /tmp/bvt-analysis-*`) - Auto-approved

**GitHub CLI Authentication**:
```bash
gh auth status
gh auth login                                    # if not authenticated
gh auth refresh -s repo -s actions:read -s gist  # ensure scopes
```

**Required Scopes**: `repo`, `actions:read`, `gist`

## When Invoked

Triggered when:
- User calls `/bvt-issue <bug description>` — create new issue + analyze
- User says `new bvt issue` followed by bug details — create new issue + analyze
- User asks to re-analyze an existing issue — skip creation, fetch issue body, extract CI link, run analysis
  - Patterns: `reanalyze #<number>`, `re-analyze #<number>`, `重新分析 #<number>`, or a full issue URL

## Process

### Single-Step Submission

1. **Extract from user's message**:
   - Test case name (e.g., `test_generic_genai.py::test_generic_genai_pipeline`)
   - Bug description (full failure message)
   - CI link (if present, e.g., GitHub Actions URL)

2. **Generate title**: Extract concise title from test name or first line (max 60 chars)

3. **Auto-submit** with defaults:
   - env: `ci`
   - query_id, instance_id, instance_link: `N/A`

4. **Return issue URL** immediately

### Issue Content Generation

```markdown
---
name: MOI Bug
about: Report a bug of MO or MO Intelligence from users that should be tracked privately.
title: "[MOI BUG]: <extracted-title>"
labels: ["kind/bug-moi", "kind/bug", "bvt-tag-issue"]
assignees: xzxiong
---

**information**
- env: ci
- query_id: N/A
- instance_id: N/A
- instance_link: N/A

**Describe the bug**
<full-user-message>

**Screenshots**
<extracted-ci-link or "N/A">

**Additional context**
BVT test failure

**How To Reproduce The Bug Step By Step**
1. Run BVT test suite
2. Execute case: <extracted-test-name>
3. Observe the failure
```

### Submission

```bash
gh issue create --repo matrixorigin/matrixflow \
  --title "[MOI BUG]: <title>" \
  --label "kind/bug-moi,kind/bug,bvt-tag-issue" \
  --assignee xzxiong \
  --body "<generated-body>"
```

### Re-Analysis of Existing Issue

1. **Extract issue number** from user message (`#8593`, full URL, etc.)
2. **Fetch issue body**:
   ```bash
   gh issue view <number> --repo matrixorigin/matrixflow --json body,title -q '.body'
   ```
3. **Extract CI run URL** from body/comments
4. **Run analysis** (below) and post as comment — skip issue creation

### Post-Submission Analysis (gh-first strategy)

After issue creation (or on re-analysis), execute a **tiered analysis** that prioritizes fast `gh` API calls before falling back to heavy artifact downloads.

#### Tier 1: gh API — Structured Failure Details (fast, ~5s)

Use `gh api` to fetch structured failure information directly from GitHub's check annotations and job metadata. This is the **primary** data source.

```bash
# 1a. Get run metadata (conclusion, timing, head_sha, jobs URL)
gh api repos/matrixorigin/matrixflow/actions/runs/<run-id> \
  --jq '{conclusion, run_started_at, updated_at, head_sha, head_branch, jobs_url}'

# 1b. Get failed jobs with step-level details
gh api repos/matrixorigin/matrixflow/actions/runs/<run-id>/jobs \
  --jq '.jobs[] | select(.conclusion=="failure") | {name, conclusion, started_at, completed_at, html_url, steps: [.steps[] | select(.conclusion=="failure") | {name, conclusion}]}'

# 1c. Get check run annotations (contains test failure messages directly)
#     First get the check_suite_id from the run, then fetch annotations per failed job
JOBS_JSON=$(gh api "repos/matrixorigin/matrixflow/actions/runs/<run-id>/jobs" --jq '.jobs[] | select(.conclusion=="failure") | .id')
for JOB_ID in $JOBS_JSON; do
  gh api "repos/matrixorigin/matrixflow/check-runs/${JOB_ID}/annotations" \
    --jq '.[] | {path, start_line, end_line, annotation_level, message, title}'
done
```

**What annotations provide**: GitHub Actions automatically creates annotations for pytest failures. Each annotation contains:
- `message`: The full assertion/error message
- `path`: Test file path
- `title`: Test name or error type
- `annotation_level`: `failure` or `warning`

If annotations contain sufficient failure details (test names + error messages), this tier alone may be enough for the analysis comment.

#### Tier 2: Failed Step Logs (medium, ~30s)

If Tier 1 annotations are empty or insufficient, fetch the failed step logs:

```bash
timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed \
  > /tmp/bvt-analysis-<run-id>/ci-logs.txt
```

Extract error context:
```bash
grep -B 50 -A 50 -E "(FAILED|ERROR|AssertionError|Exception|Traceback)" ci-logs.txt | head -200
```

#### Tier 3: Artifact Download (heavy, ~2-5min)

Only download artifacts when Tier 1+2 don't provide enough root-cause information (e.g., service-side errors needed).

| Artifact | Contents | When to download |
|----------|----------|-----------------|
| `logs` | Service logs (connector, apiserver, scheduler, job-consumer.1-8, augmentation, matrixflow-mo, test_results) | When test failure suggests service-side issue |
| `bvt-runlog` | pytest.log | When need full test execution trace |
| `allure-results` | Allure JSON files | Rarely needed for issue analysis |

```bash
WORK_DIR="/tmp/bvt-analysis-<run-id>"
gh run download <run-id> --repo matrixorigin/matrixflow --name logs --dir "$WORK_DIR/artifacts/logs"
gh run download <run-id> --repo matrixorigin/matrixflow --name bvt-runlog --dir "$WORK_DIR/artifacts/bvt-runlog"
```

Analyze service logs:
- **First**: If error messages contain port numbers, use the Port-to-Service Mapping (below) to identify the responsible service and prioritize its log file
- Scan the targeted service log for `ERROR`, `FATAL`, `panic`, `exception`, `Traceback` around the failure timestamp (±2 minutes)
- Then scan remaining `*.log` files for `ERROR`, `FATAL`, `panic`, `exception`, `Traceback`
- Key services: apiserver, connector, job-consumer.*, augmentation, matrixflow-mo
- Check `test_results/` for generic_genai comparison output

#### Decision Logic

```
Tier 1 (gh api annotations + jobs)
  ├─ Annotations have failure details → compose comment, skip Tier 2/3
  └─ Annotations empty/insufficient
       ├─ Tier 2 (--log-failed)
       │    ├─ Error context found → compose comment, optionally Tier 3
       │    └─ Logs empty/timeout → Tier 3
       └─ Tier 3 (artifact download)
            └─ Analyze service logs + pytest.log → compose comment
```

**Always download artifacts** in practice — the tiered approach determines what goes into the comment first, but artifacts provide the full picture. Start Tier 1 immediately, and kick off artifact downloads in parallel when possible.

#### Upload & Comment

Upload all collected logs to a Gist:
```bash
gh gist create --public --desc "BVT Issue #<number> - CI logs for run <run-id>" <files...>
```

Post analysis comment to issue:
```bash
gh issue comment <number> --repo matrixorigin/matrixflow --body "<comment>"
```

Comment structure:
```markdown
## CI Log Analysis

**Run**: https://github.com/matrixorigin/matrixflow/actions/runs/<run-id>
**Conclusion**: failure | **Branch**: <branch> | **SHA**: <sha>
**Full Logs**: <gist-url>

### Failed Jobs & Steps
<from Tier 1: job names, failed steps>

### Test Failure Annotations
<from Tier 1: annotation messages — the most valuable section>

### Suspected Service: <service-name> (port <port>)
<if error contains port info: mapped service, targeted log excerpts>

### CI Step Log Errors
<from Tier 2: grep'd error context>

### Pytest Log Summary
<from Tier 3: bvt-runlog artifact>

### Service Log Errors
<from Tier 3: logs artifact, grouped by service>
```

Comment body truncated to 60KB (GitHub limit).

### Required Shell Commands & Permissions

- `gh api repos/<owner>/<repo>/actions/runs/<id>` — `actions:read`
- `gh api repos/<owner>/<repo>/actions/runs/<id>/jobs` — `actions:read`
- `gh api repos/<owner>/<repo>/check-runs/<id>/annotations` — `actions:read`
- `gh run view <id> --log-failed` — `actions:read`
- `gh run download <id> --name <artifact>` — `actions:read`
- `gh gist create` — `gist`
- `gh issue create / comment / view` — `repo`
- `timeout`, `grep`, `head`, `tail`, `cat`, `find`, `jq` — log processing

## Port-to-Service Mapping & Targeted Log Analysis

When error messages contain port numbers (e.g., `127.0.0.1:8910: read: connection reset by peer`), extract the port and map it to the responsible service using this table:

| Port  | Service             | Log File(s)                  |
|-------|---------------------|------------------------------|
| 5173  | frontend            | —                            |
| 8000  | local-service       | `local-service.log`          |
| 30008 | license-service     | `license.log`                |
| 8910  | byoa/api-server     | `apiserver.log`              |
| 8911  | byoa/job-consumer   | `job_consumer.*.log`         |
| 8920  | catalog-service     | `catalog.log`                |
| 9000  | connector-rpc       | `connector.log`              |
| 9527  | agent-runtime       | —                            |
| 9528  | agent-profiling     | —                            |
| 6001  | mo                  | `matrixflow-mo.log`          |
| 9100  | minio               | —                            |
| 9101  | minio               | —                            |
| 8080  | rocketmq            | —                            |
| 8081  | rocketmq            | —                            |
| 8082  | rocketmq            | —                            |
| 2003  | unoserver           | —                            |
| 50051 | mowl.scheduler      | `mowl.log`                   |
| 50052 | mowl.worker         | `mowl.log`                   |

### How to Use

1. **Extract ports from error messages**: Parse FAILED lines and error context for patterns like `127.0.0.1:<port>`, `localhost:<port>`, `0.0.0.0:<port>`.
2. **Identify the service**: Look up the port in the table above.
3. **Prioritize that service's log**: When analyzing artifacts, focus on the mapped log file first. Grep for errors around the failure timestamp (±2 minutes).
4. **Include in analysis comment**: Add a "Suspected Service" section that names the service, the port, and relevant log excerpts.

Example: if the error is `read tcp 127.0.0.1:55602->127.0.0.1:8910: read: connection reset by peer`:
- Target port = **8910** → service = **byoa/api-server** → log = **`apiserver.log`**
- Grep `apiserver.log` for `ERROR|FATAL|panic|restart|shutdown` around the failure time
- Also check `local-service.log` (port 8000, the proxy layer) for related proxy errors

### Analysis Comment Addition

When a port-to-service mapping is identified, add this section to the comment:

```markdown
### Suspected Service: <service-name> (port <port>)

Error indicates the **<service-name>** (port <port>) reset the connection.

**<log-file> errors around failure time (<timestamp> ±2min):**
<relevant error lines from the service log>
```

## Implementation Notes

- **Zero interaction**: Extract everything from initial message, no confirmation
- **gh-first**: Always start with `gh api` for structured data before downloading logs
- **Parallel where possible**: Start artifact download while processing Tier 1 results
- **Port-aware analysis**: Extract port numbers from error messages, map to services, and prioritize corresponding log files
- Default env to `ci`, skip query_id/instance_id/instance_link (always N/A)
- Auto-extract test case name: `test_*.py::test_*`, `FAILED test_*`, `src/tests/.../test_*.py::test_*`
- Auto-extract CI links from GitHub Actions URLs (run-level and job-level)
- Generate concise title (max 60 chars) from test name
- **Log fetch timeout**: 30 minutes (1800 seconds)
- **Temp files**: `/tmp/bvt-analysis-<run-id>/`, cleaned up after posting

## Example Flow

```
User: /bvt-issue FAILED test_generic_genai.py::test_generic_genai_pipeline - 3 cases failed
      https://github.com/matrixorigin/matrixflow/actions/runs/23041870759

Claude: ✅ Issue created: https://github.com/matrixorigin/matrixflow/issues/8593
        
        Fetching BVT failure details via gh API...
        Found 3 failure annotations, 1 failed job (Run BVT cases)
        Downloading artifacts for full analysis...
        ✅ Analysis posted to issue #8593
```

```
User: reanalyze #8593

Claude: Fetching issue #8593...
        Found CI link: https://github.com/matrixorigin/matrixflow/actions/runs/23041870759
        
        Fetching BVT failure details via gh API...
        ✅ Analysis posted to issue #8593
```

## Reference Script

`skills/bvt-issue/scripts/analyze-ci-logs.sh` — standalone implementation of the full analysis pipeline.
