---
name: bvt-issue
description: Create or re-analyze a MatrixFlow BVT bug issue with zero-interaction issue submission plus CI log analysis. Use for `/bvt-issue`, BVT bug descriptions with CI URLs, or `reanalyze #<issue>`.
---

# BVT Issue

Submit or re-analyze a BVT bug issue, then attach CI evidence.

## Modes

- New issue: input contains a failure description and optional CI URL.
- Re-analysis: input says `reanalyze`, `re-analyze`, or `重新分析` plus an issue number.

## Workflow

1. For new issues, extract test case, failure summary, and CI URL from the user message.
2. Create a `matrixorigin/matrixflow` issue with labels `kind/bug-moi,kind/bug,bvt-tag-issue` and assignee `xzxiong`.
   - Title: `[MOI BUG]: <title-max-60-chars>`.
   - Body: env=`ci`; query_id/instance_id/instance_link=`N/A`; preserve the full user failure text; include the CI link in screenshots/logs; include reproduction from the failed test.
   - Return the issue URL immediately, then continue analysis.
3. For re-analysis, fetch the existing issue and comments, then extract the CI URL.
4. Analyze CI in tiers:
   - Tier 1: `gh api` metadata, failed jobs, failed steps, and annotations. If annotations are sufficient, skip slower tiers.
   - Tier 2: `timeout 1800 gh run view <run-id> --repo matrixorigin/matrixflow --log-failed`.
   - Tier 3: download `logs` and `bvt-runlog` artifacts when step logs are empty, timed out, or not enough.
5. Use port-to-service mapping to prioritize service logs.
6. For port errors like `127.0.0.1:8910: connection reset`, map the port and grep that service log within about +/-2 minutes of the failure.
7. Upload critical logs to a public gist when useful.
8. Comment on the issue with: run info, failed jobs/steps, annotations, suspected service, CI step errors, pytest summary, service log errors, root cause, and next fix. Keep below GitHub limits.

## Notes

- Store temporary files under `/tmp/bvt-analysis-<run-id>/` and clean them up after posting.
- Port hints: `8910` api-server, `8911` job-consumer, `9000` connector-rpc, `6001` MatrixOne, `50051`/`50052` mowl.
