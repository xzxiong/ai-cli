---
name: ci-issue
description: |
  Analyze CI failures from GitHub Actions and submit issues. Works for any CI workflow (Moi-Core CI, BVT, etc.).

  Use this skill when:
  - The user invokes `/ci-issue <ci-url>`
  - The user says "ci issue" or "new ci issue" followed by a GitHub Actions URL
  - The user provides a CI failure URL and asks to create an issue

  The skill automatically fetches CI logs, analyzes failures, creates a GitHub issue, and posts analysis as a comment.

  **Agent**: Uses `ci-issue-agent` with pre-configured shell command permissions.
---

# CI Issue Submission & Analysis Skill

## Purpose

Analyze GitHub Actions CI failures from the `matrixorigin/matrixflow` monorepo, create a GitHub issue, and post detailed analysis — all in one step.

The code lives in `{monorepo}/moi-core`. The primary CI workflow is **Moi-Core CI** (`.github/workflows/moi-core-ci.yml`).

## Prerequisites

**Agent**: `ci-issue-agent` (`.kiro/agents/ci-issue-agent.json`)

**GitHub CLI Scopes**: `repo`, `actions:read`, `gist`
```bash
gh auth refresh -s repo -s actions:read -s gist
```

## When Invoked

- `/ci-issue <ci-url>` — analyze + create issue
- `ci issue` / `new ci issue` + GitHub Actions URL

## Moi-Core CI Structure

The workflow runs a single job `moi-core test with MatrixOne and coverage` that:
1. Checks out the monorepo, sets up Go 1.24+1.25 toolchain, Python 3.11, Docker Compose
2. Starts MatrixOne via Docker (`make start-mo && make wait-mo`)
3. Runs 3 test stages sequentially, each producing a log:

| Make Target | Log File | What It Tests |
|-------------|----------|---------------|
| `ci-test` | `ci-test.log` | `make lint` + `make doc` (swagger gen + doc consistency) + Go unit tests with coverage |
| `test-python-sdk` | `test-python-sdk.log` | Python SDK unit tests (`pytest python-sdk/tests`) + Go integration tests (`moi-core/tests/`) |
| `test` | `test.log` | Full Go test suite with race detection and coverage |

4. Uploads artifact `moi-core-ci-artifacts` containing:
   - `dist/logs/` — `ci-test.log`, `test-python-sdk.log`, `test.log`, `ci-exit-code`
   - `dist/coverage/` — coverage reports

### Port-to-Module Mapping

When CI logs contain `connection refused`, `bind: address already in use`, or other port-related errors, use this table to identify the affected module:

**moi-core 内部服务：**

| Port | Module | Description |
|------|--------|-------------|
| 8081 | `moi-core/catalog` (HTTP) | Catalog 主 API；内嵌 Mowl 时 gRPC 通过 cmux 复用此端口 |
| 8082 | `moi-core/catalog` (gRPC) | 独立 gRPC 端口，仅 `mowl.embedded=false` 时使用 |
| 50051 | `moi-core/mowl` (gRPC) | Mowl 引擎独立部署时的 gRPC 端口 |
| 8080 | `moi-core/workers/go-worker` | Go Worker 默认连接 Mowl 的 endpoint |

**Monorepo 其他服务：**

| Port | Module | Description |
|------|--------|-------------|
| 8000 | `local-service` | RBAC 网关，所有 API 入口 |
| 8910 | `workflow_be` | Python/FastAPI 工作流引擎 |
| 9000 | `connector_rpc` | Go/tRPC 数据连接器 |
| 8920 | `catalog_service` | Go/Gin 数据目录 |
| 9527/9528 | `agent_be` | AI Agent (Runtime/Profiling) |
| 8817 | `openxml_service` | C#/.NET 文档解析 |

**基础设施：**

| Port | Service |
|------|---------|
| 6001 | MatrixOne (MySQL 协议) |
| 9100/9101 | MinIO (API/Console) |
| 8080-8082 | RocketMQ (Dashboard/Broker) |
| 2003 | UnoServer |

### Common Failure Types

| Type | Pattern | Where to Look |
|------|---------|---------------|
| Go compilation error | `undefined`, `cannot use`, `has no field or method` | `test-python-sdk.log` (integration tests), `test.log` |
| Doc inconsistency | `与源码不一致，请运行: make doc-update` | `ci-test.log` |
| Lint failure | `golangci-lint`, `staticcheck` | `ci-test.log` |
| Unit test failure | `--- FAIL: Test*`, `FAIL\tgithub.com/matrixflow/moi-core/...` | `test.log` |
| Integration test failure | `FAIL\tgithub.com/matrixflow/moi-core/tests` | `test-python-sdk.log` |
| Python SDK test failure | `FAILED`, `AssertionError` | `test-python-sdk.log` |
| MatrixOne startup failure | `wait-mo`, `connection refused` | `ci-test.log` (early) |
| Port conflict / connection refused | `bind: address already in use`, `connection refused :PORT` | any log — 参照上方端口表定位模块 |
| Timeout | `CI_TEST_TIMEOUT` (default 40m) | any log |

## Process

### Step 1: Parse URL & Fetch Metadata

```bash
# Extract run-id and optional job-id from URL
# URL patterns:
#   actions/runs/<run-id>
#   actions/runs/<run-id>/job/<job-id>

gh api repos/matrixorigin/matrixflow/actions/runs/<run-id> \
  --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch, name, display_title, event}'
```

### Step 2: Tiered Log Analysis (gh-first)

#### Tier 1: gh API (fast, ~5s)

```bash
# Failed jobs + steps
gh api repos/matrixorigin/matrixflow/actions/runs/<run-id>/jobs --paginate \
  --jq '.jobs[] | select(.conclusion=="failure") | {name, html_url, failed_steps: [.steps[] | select(.conclusion=="failure") | .name]}'

# Annotations (GitHub auto-creates these for Go test failures)
for JOB_ID in <failed-job-ids>; do
  gh api repos/matrixorigin/matrixflow/check-runs/${JOB_ID}/annotations \
    --jq '.[] | select(.annotation_level=="failure") | {path, start_line, message, title}'
done
```

Annotations are the most valuable — they contain Go compiler errors and test failure messages directly.

#### Tier 2: Artifact Download (primary data source for moi-core)

For Moi-Core CI, artifacts are always the best source since `gh run view --log-failed` often returns empty (the job uses `set +e` and deferred exit).

```bash
WORK_DIR="/tmp/ci-issue-<run-id>"
mkdir -p "$WORK_DIR/artifacts"

gh run download <run-id> --repo matrixorigin/matrixflow \
  --name moi-core-ci-artifacts --dir "$WORK_DIR/artifacts"
```

Analyze each log file:
```bash
# Check which stage failed
cat "$WORK_DIR/artifacts/logs/ci-exit-code"

# Scan for errors in each log
for LOG in ci-test.log test-python-sdk.log test.log; do
  grep -n -E "(FAIL|ERROR|undefined|cannot use|has no field|panic|Traceback|exit status|connection refused|bind: address already in use)" \
    "$WORK_DIR/artifacts/logs/$LOG" | tail -30
done

# If port-related errors found, extract port number and identify module
grep -oP '(?:connection refused|bind: address already in use).*?:(\d+)' "$WORK_DIR/artifacts/logs/"*.log | \
  while read -r line; do
    PORT=$(echo "$line" | grep -oP ':\d+' | tail -1 | tr -d ':')
    case "$PORT" in
      8081) echo "→ Module: moi-core/catalog (HTTP)" ;;
      8082) echo "→ Module: moi-core/catalog (gRPC)" ;;
      50051) echo "→ Module: moi-core/mowl (gRPC)" ;;
      8080) echo "→ Module: go-worker or RocketMQ" ;;
      6001) echo "→ Module: MatrixOne (database)" ;;
      8000) echo "→ Module: local-service (RBAC)" ;;
      8910) echo "→ Module: workflow_be" ;;
      9000) echo "→ Module: connector_rpc" ;;
      8920) echo "→ Module: catalog_service" ;;
      9527|9528) echo "→ Module: agent_be" ;;
      8817) echo "→ Module: openxml_service" ;;
      9100|9101) echo "→ Module: MinIO" ;;
      2003) echo "→ Module: UnoServer" ;;
      *) echo "→ Unknown port: $PORT" ;;
    esac
  done
```

#### Tier 3: Failed Step Logs (fallback)

Only if artifacts are unavailable:
```bash
timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed > "$WORK_DIR/ci-logs.txt"
```

### Step 3: Create Issue

```bash
gh issue create --repo matrixorigin/matrixflow \
  --title "[CI BUG]: <workflow-name> - <failure-summary>" \
  --label "kind/bug-moi,kind/bug" \
  --assignee xzxiong \
  --body "<generated-body>"
```

Issue body:
```markdown
**CI Run**: <run-url>
**Workflow**: <workflow-name>
**Branch**: <branch> | **SHA**: <sha> | **PR**: <pr-link-if-available>
**Trigger**: <event-type>

**Failed Jobs**:
- <job-name>: <failed-steps>

**Error Summary**:
<concise-error-description>

**Screenshots**
<ci-job-url>

**Additional context**
CI failure from workflow: <workflow-name>
```

### Step 4: Post Analysis Comment

Upload logs to Gist, then post structured analysis:

```bash
gh gist create --public --desc "CI Issue #<number> - <workflow> run <run-id>" <log-files...>
gh issue comment <number> --repo matrixorigin/matrixflow --body "<analysis>"
```

Comment structure:
```markdown
## CI Log Analysis

**Run**: <run-url>
**Workflow**: <workflow-name>
**Conclusion**: failure | **Branch**: <branch> | **SHA**: <sha>
**Full Logs**: <gist-url>

### Failed Jobs & Steps
<from Tier 1>

### Test Failure Annotations
<from Tier 1: compiler errors, test failures>

### Failed Stage: <ci-test|test-python-sdk|test>

#### Port/Service Errors
<if any: connection refused / bind errors — with port→module mapping>

#### Compilation Errors
<if any: undefined symbols, type mismatches — with file:line>

#### Test Failures
<FAIL lines grouped by package>

#### Doc/Lint Issues
<if any>

### Root Cause & Fix
<concise analysis of what broke and what needs to change>
```

Comment body truncated to 60KB (GitHub limit).

## Implementation Notes

- **Zero interaction**: Extract everything from CI URL, no confirmation
- **Artifact-first for moi-core**: Unlike BVT, moi-core CI artifacts (`ci-test.log`, `test-python-sdk.log`, `test.log`) are the primary data source since `--log-failed` often returns empty
- **Stage-aware analysis**: Identify which of the 3 make targets failed and focus analysis there
- **Log fetch timeout**: 30 minutes (1800 seconds)
- **Temp files**: `/tmp/ci-issue-<run-id>/`, cleaned up after posting

## Example Flow

```
User: /ci-issue https://github.com/matrixorigin/matrixflow/actions/runs/23293089386/job/67733411477?pr=8569

Claude: Fetching CI run metadata...
        Workflow: Moi-Core CI | Branch: refactor-parser-v1-to-core-openxml | Status: failure

        Downloading moi-core-ci-artifacts...
        ci-exit-code: 2
        Failed stage: ci-test (doc inconsistency), test-python-sdk (compilation errors)

        Compilation errors in integration tests:
        - client.MinerU undefined (mineru_integration_test.go)
        - client.OfficeConverter undefined (office_converter_integration_test.go)
        - client.OpenXML undefined (xlsx_integration_test.go)

        ✅ Issue created: https://github.com/matrixorigin/matrixflow/issues/8672
        ✅ Analysis posted to issue
```

## Required Shell Commands

- `gh api repos/matrixorigin/matrixflow/actions/runs/<id>` — run metadata
- `gh api repos/matrixorigin/matrixflow/actions/runs/<id>/jobs` — job details
- `gh api repos/matrixorigin/matrixflow/check-runs/<id>/annotations` — failure annotations
- `gh run download <id> --name moi-core-ci-artifacts` — artifact download
- `gh run view <id> --log-failed` — fallback log fetch
- `gh gist create` — log upload
- `gh issue create / comment` — issue management
- `timeout`, `grep`, `head`, `tail`, `cat`, `find`, `wc` — log processing
