---
name: bvt-analyze
description: Analyze BVT failures from a GitHub Actions run or job URL, inspect logs/artifacts, create a MatrixFlow bug issue, and post a structured analysis. Use for `/bvt-analyze`, BVT CI failure analysis, or requests to create an issue from BVT logs.
---

# BVT Analyze

Analyze MatrixFlow BVT failures and open a high-signal bug issue.

## Workflow

1. Extract `run-id` and optional `job-id` from a GitHub Actions URL.
2. Fetch run metadata and failed jobs via `gh api`.
3. Prefer annotations first; they often contain test failure messages directly.
4. If annotations are insufficient, read failed step logs with `gh run view --log-failed`.
5. If still insufficient, download `logs` and `bvt-runlog` artifacts into `/tmp/bvt-<run-id>/`.
6. Map connection errors by port to the likely service:
   - `8910` api-server, `8911` job-consumer, `9000` connector-rpc
   - `8920` catalog-service, `6001` MatrixOne, `8000` local-service
   - `50051`/`50052` mowl
7. Create a `matrixorigin/matrixflow` issue labeled `kind/bug-moi,kind/bug,bvt-tag-issue` and assigned to `xzxiong`.
8. Post an analysis comment with run info, failed jobs, annotations, suspected service, root cause, and artifact/log links.

## Output

- Issue URL.
- Summary of the first failed test, likely failing service, and evidence used.
- Any remaining uncertainty if artifacts or logs were unavailable.
