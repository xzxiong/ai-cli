Analyze CI failures from GitHub Actions and submit issues. Works for any CI workflow (Moi-Core CI, BVT, etc.).

Input: $ARGUMENTS (GitHub Actions CI URL)

## Process

### 1. Parse URL & Fetch Metadata
```bash
gh api repos/matrixorigin/matrixflow/actions/runs/<run-id> \
  --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch, name, display_title, event}'
```

### 2. Tiered Log Analysis (gh-first)

**Tier 1: gh API (fast)**
- Failed jobs + steps with `--paginate`
- Annotations from failed check runs (Go compiler errors, test failures)

**Tier 2: Artifact download (primary for moi-core)**
```bash
gh run download <run-id> --repo matrixorigin/matrixflow --name moi-core-ci-artifacts --dir /tmp/ci-issue-<run-id>/artifacts
```
Moi-Core CI artifacts contain: `ci-test.log`, `test-python-sdk.log`, `test.log`, `ci-exit-code`

Check which stage failed and scan each log for:
`FAIL|ERROR|undefined|cannot use|has no field|panic|Traceback|exit status|connection refused|bind: address already in use`

**Port-to-Module mapping** for connection errors:
| Port | Module |
|------|--------|
| 8081 | moi-core/catalog (HTTP) |
| 8082 | moi-core/catalog (gRPC) |
| 50051 | moi-core/mowl (gRPC) |
| 6001 | MatrixOne |
| 8000 | local-service |
| 8910 | workflow_be |
| 9000 | connector_rpc |

**Common failure types**: Go compilation error, doc inconsistency (`make doc-update`), lint failure, unit/integration test failure, Python SDK test failure, MO startup failure, port conflict, timeout.

**Tier 3: Fallback** — `gh run view --log-failed` (only if artifacts unavailable)

### 3. Create Issue
```bash
gh issue create --repo matrixorigin/matrixflow \
  --title "[CI BUG]: <workflow-name> - <failure-summary>" \
  --label "kind/bug-moi,kind/bug" --assignee xzxiong \
  --body "<body-with-run-url-workflow-branch-sha-error-summary>"
```

### 4. Post Analysis Comment
Upload logs to Gist, then post structured analysis:
```bash
gh gist create --public --desc "CI Issue #<number> - <workflow> run <run-id>" <log-files...>
gh issue comment <number> --repo matrixorigin/matrixflow --body "<analysis>"
```

Comment: Failed Jobs → Annotations → Stage Errors (compilation/test/doc/lint) → Port/Service Errors → Root Cause & Fix. Truncate to 60KB.

Temp files in `/tmp/ci-issue-<run-id>/`, clean up after posting.
