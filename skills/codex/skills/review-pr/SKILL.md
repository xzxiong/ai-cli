---
name: review-pr
description: Review GitHub pull requests from a PR URL or number and produce a structured Chinese code review. Use for `review pr`, `/review-pr`, `代码审查`, `看下这个 PR`, exploratory review with `--explore`, ops review with `--ops`, or PRs from ops/gitops/moi-gitops/moi-op repositories.
---

# Review PR

Perform evidence-backed PR review in Chinese.

## Modes

- Standard: production-oriented code quality, tests, performance, safety, and prompt quality.
- Explore: demo/PoC review focused on approach, consistency, observability, and iteration.
- Ops: infrastructure/deployment review focused on resources, security, rollout, and environment impact.

Choose `--explore` and `--ops` explicitly when present. Auto-use Ops for `ops`, `gitops`, `moi-gitops`, and `moi-op`.

## Workflow

1. Resolve owner/repo and PR number.
2. Fetch metadata with `gh pr view`.
3. Read the diff selectively with `gh pr diff`; skip generated files unless behavior changes.
4. If `--with-issue` is present, fetch linked issue context.
5. Read the matching checklist:
   - `references/standard-checklist.md`
   - `references/explore-checklist.md`
   - `references/ops-checklist.md`
6. Produce a structured review with severity levels:
   - 🔴 must fix
   - 🟡 should fix
   - 🟢 optional
7. Archive to `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`, rotating existing files with `_bakNNN`.
8. Minimize prior review comments from the current user when they match the review-report signature.
9. Post the new review as a PR comment.

## Review Standard

Lead with concrete findings. Each finding needs file/line evidence, behavioral impact, and a practical fix.
