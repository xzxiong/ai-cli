---
name: turbo-issue-fix
description: "End-to-end fix workflow for matrixorigin/turbo GitHub issues: analyze issue, design, comment, add tests, implement fix, run regression, and summarize. Use for `/turbo-issue-fix` or requests to fix a Turbo issue."
---

# Turbo Issue Fix

Fix a `matrixorigin/turbo` GitHub issue with an auditable workflow.

## Workflow

1. Fetch the issue and optional referenced comment.
2. Extract symptoms, reproduction steps, affected modules, and expected behavior.
3. Locate code in Turbo:
   - backend: `pkg/model`, `pkg/api`, `pkg/engine`, `pkg/governance`, `pkg/agent`, `pkg/store`
   - frontend: `apps/web`
4. Post a design comment with root cause, planned files, impact, and validation plan.
5. Add or update tests before the fix where feasible:
   - Go backend tests through `make ut` or `make ci`.
   - Frontend E2E through `make web-e2e`; `next build` is baseline validation.
6. Implement the minimal fix using explicit structs, `pkg/xid.New()` for IDs, pointer nullable fields, `(limit, offset)` pagination, and idempotency keys on critical writes.
7. Run regression validation.
8. Summarize changed files, tests, and any residual risk.

## Gotchas

- Do not use raw `go test` when project Make targets are expected.
- `apps/web` uses static export; `next start` is not valid.
- E2E mocks intercept `apiBase`, which defaults to `http://127.0.0.1:3000`; account for URL normalization in browser-origin tests.
