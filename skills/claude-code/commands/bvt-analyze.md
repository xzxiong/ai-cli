Analyze BVT test failures from GitHub Actions CI logs, then create issue with analysis.

Input: $ARGUMENTS (GitHub Actions run URL or job URL)

## Process

1. Parse CI URL to extract run-id and optional job-id from patterns:
   - `actions/runs/<run-id>`
   - `actions/runs/<run-id>/job/<job-id>`

2. **Tier 1: gh API (fast)**
   ```bash
   gh api repos/matrixorigin/matrixflow/actions/runs/<run-id> \
     --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch}'

   gh api repos/matrixorigin/matrixflow/actions/runs/<run-id>/jobs --paginate \
     --jq '.jobs[] | select(.conclusion=="failure") | {name, html_url, failed_steps: [.steps[] | select(.conclusion=="failure") | .name]}'

   # Annotations (contain test failure messages directly)
   for each failed job-id:
     gh api repos/matrixorigin/matrixflow/check-runs/<job-id>/annotations \
       --jq '.[] | select(.annotation_level=="failure") | {path, start_line, message, title}'
   ```

3. **Tier 2: Failed step logs** (if Tier 1 insufficient)
   ```bash
   timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed > /tmp/bvt-<run-id>/ci-logs.txt
   grep -B 50 -A 50 -E "(FAILED|ERROR|AssertionError|Exception|Traceback)" ci-logs.txt | head -200
   ```

4. **Tier 3: Artifact download** (if Tier 1+2 insufficient)
   ```bash
   gh run download <run-id> --repo matrixorigin/matrixflow --name logs --dir /tmp/bvt-<run-id>/artifacts/logs
   gh run download <run-id> --repo matrixorigin/matrixflow --name bvt-runlog --dir /tmp/bvt-<run-id>/artifacts/bvt-runlog
   ```
   Scan service logs for `ERROR|FATAL|panic|exception|Traceback`.

5. **Port-to-Service mapping** for error diagnosis:
   | Port | Service | Log File |
   |------|---------|----------|
   | 8910 | byoa/api-server | apiserver.log |
   | 8911 | byoa/job-consumer | job_consumer.*.log |
   | 9000 | connector-rpc | connector.log |
   | 8920 | catalog-service | catalog.log |
   | 6001 | mo | matrixflow-mo.log |
   | 8000 | local-service | local-service.log |
   | 50051 | mowl.scheduler | mowl.log |

6. **Auto-create BVT Issue**:
   ```bash
   gh issue create --repo matrixorigin/matrixflow \
     --title "[MOI BUG]: <first-failed-test> - <error-summary>" \
     --label "kind/bug-moi,kind/bug,bvt-tag-issue" --assignee xzxiong \
     --body "<failure-details>"
   ```

7. **Post analysis as comment**:
   - Create zip of critical logs: `zip -r /tmp/bvt-issue-<run-id>.zip *.log`
   - Upload to Gist: `gh gist create --public --desc "BVT Issue #<number>" <files...>`
   - Comment with: critical error timeline, top 50 error lines, root cause, artifact download instructions
   - Truncate comment to 60KB

Temp files in `/tmp/bvt-<run-id>/`, clean up after completion.
