---
name: bvt-analyze
description: Analyze BVT failures from a GitHub Actions run or job URL, inspect logs/artifacts, create a MatrixFlow bug issue, and post a structured analysis. Use for `/bvt-analyze`, BVT CI failure analysis, or requests to create an issue from BVT logs.
---

# BVT Analyze

Analyze MatrixFlow BVT failures and open a high-signal bug issue.

## Workflow

1. Extract `run-id` and optional `job-id` from a GitHub Actions URL.
2. Fetch run metadata and failed jobs via `gh api`, including conclusion, start/update time, branch, short SHA, failed job names, and failed steps.
3. Prefer check-run annotations first; they often contain the exact test file, line, assertion, and error message.
4. If annotations are insufficient, read failed step logs:
   - `timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed`
   - grep around `FAILED`, `ERROR`, `AssertionError`, `Exception`, and `Traceback`.
5. If still insufficient, download artifacts into `/tmp/bvt-<run-id>/`:
   - artifact `logs`
   - artifact `bvt-runlog`
   Scan service logs for `ERROR`, `FATAL`, `panic`, `exception`, and `Traceback`.
6. Map connection errors by port to the likely service:
   - `8910` api-server, `8911` job-consumer, `9000` connector-rpc
   - `8920` catalog-service, `6001` MatrixOne, `8000` local-service
   - `50051`/`50052` mowl
7. Create a `matrixorigin/matrixflow` issue labeled `kind/bug-moi,kind/bug,bvt-tag-issue` and assigned to `xzxiong`.
8. Upload critical logs to a public gist when useful. Keep comments below 60KB.
9. Post an analysis comment with run info, failed jobs, failed steps, annotations, suspected service, critical error timeline, top error lines, likely root cause, and artifact/log links.

## Output

- Issue URL.
- Summary of the first failed test, likely failing service, and evidence used.
- Any remaining uncertainty if artifacts or logs were unavailable.
