Zero-interaction BVT bug issue submission + CI log analysis.

Input: $ARGUMENTS (bug description with optional CI URL, OR "reanalyze #<number>")

## Mode Detection

- Contains `reanalyze` / `re-analyze` / `重新分析` + issue number → **Re-analysis mode**: skip issue creation, fetch existing issue, extract CI URL, run analysis
- Otherwise → **New issue mode**: create issue + analyze

## New Issue Mode

1. **Extract from user message**:
   - Test case name: `test_*.py::test_*`, `FAILED test_*`, `src/tests/.../test_*.py::test_*`
   - Bug description (full failure message)
   - CI link (GitHub Actions URL)

2. **Auto-submit**:
   ```bash
   gh issue create --repo matrixorigin/matrixflow \
     --title "[MOI BUG]: <title-max-60-chars>" \
     --label "kind/bug-moi,kind/bug,bvt-tag-issue" \
     --assignee xzxiong \
     --body "<body>"
   ```
   Body template: env=ci, query_id/instance_id/instance_link=N/A, full user message as description, CI link in Screenshots, test reproduction steps.

3. **Return issue URL immediately**, then proceed to analysis.

## Re-analysis Mode

1. Extract issue number from user message
2. Fetch issue body: `gh issue view <number> --repo matrixorigin/matrixflow --json body,title -q '.body'`
3. Extract CI run URL from body/comments
4. Run analysis (below) and post as comment

## Post-Submission Analysis (tiered, gh-first)

**Tier 1: gh API (fast, ~5s)**
- Run metadata, failed jobs with step details, check run annotations
- Annotations provide: full assertion/error message, test file path, test name, annotation level

**Tier 2: Failed step logs (~30s)**
- `timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed`

**Tier 3: Artifact download (~2-5min)**
- Download `logs` and `bvt-runlog` artifacts
- Scan service logs using Port-to-Service mapping:
  | Port | Service | Log File |
  |------|---------|----------|
  | 8910 | byoa/api-server | apiserver.log |
  | 8911 | byoa/job-consumer | job_consumer.*.log |
  | 9000 | connector-rpc | connector.log |
  | 6001 | mo | matrixflow-mo.log |
  | 50051/50052 | mowl | mowl.log |

**Decision logic**: Tier 1 annotations sufficient → compose comment, skip Tier 2/3. Annotations empty → Tier 2. Logs empty/timeout → Tier 3. Always download artifacts in parallel for full picture.

**Port-to-Service targeted analysis**: Extract port from error messages (e.g., `127.0.0.1:8910: connection reset`) → map to service → prioritize that service's log → grep for errors ±2 minutes of failure.

**Upload & Comment**:
```bash
gh gist create --public --desc "BVT Issue #<number> - CI logs for run <run-id>" <files...>
gh issue comment <number> --repo matrixorigin/matrixflow --body "<analysis>"
```

Comment structure: Run info → Failed Jobs & Steps → Test Failure Annotations → Suspected Service (port mapping) → CI Step Log Errors → Pytest Log Summary → Service Log Errors. Truncate to 60KB.

Temp files in `/tmp/bvt-analysis-<run-id>/`, clean up after posting.
