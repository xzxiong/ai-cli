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
3. For re-analysis, fetch the existing issue and comments, then extract the CI URL.
4. Analyze CI in tiers:
   - `gh api` metadata, failed jobs, failed steps, and annotations.
   - `gh run view --log-failed` if annotations are insufficient.
   - Download artifacts when step logs are not enough.
5. Use port-to-service mapping to prioritize service logs.
6. Upload critical logs to a public gist when useful.
7. Comment on the issue with a concise evidence-based analysis, truncated below GitHub limits.

## Notes

- Return the issue URL immediately after creation, then continue analysis.
- Store temporary files under `/tmp/bvt-analysis-<run-id>/` and clean them up after posting.
