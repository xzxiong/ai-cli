---
name: ci-issue
description: Analyze MatrixFlow GitHub Actions CI failures from a run URL and create a structured GitHub issue. Use for `/ci-issue`, Moi-Core CI failures, BVT-like CI failures, or requests to submit an issue from CI logs.
---

# CI Issue

Analyze general MatrixFlow CI failures and create a bug issue.

## Workflow

1. Parse the GitHub Actions URL and fetch run metadata from `matrixorigin/matrixflow`.
2. Gather failed jobs, failed steps, and check-run annotations via `gh api`.
3. For Moi-Core CI, download `moi-core-ci-artifacts` first; inspect `ci-test.log`, `test-python-sdk.log`, `test.log`, and `ci-exit-code`.
4. Fall back to `gh run view --log-failed` only when artifacts are unavailable.
5. Classify the failure: compilation, docs update, lint, unit/integration test, Python SDK, MO startup, port conflict, or timeout.
6. Create an issue labeled `kind/bug-moi,kind/bug`, assigned to `xzxiong`.
7. Post an analysis comment with failed jobs, annotations, stage errors, port/service evidence, and a likely fix.

## Port Hints

- `8081`/`8082`: moi-core catalog
- `50051`: mowl
- `6001`: MatrixOne
- `8000`: local-service
- `8910`: workflow_be
- `9000`: connector_rpc
