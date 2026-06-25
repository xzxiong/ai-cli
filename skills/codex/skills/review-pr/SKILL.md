---
name: review-pr
description: "Review GitHub pull requests from a PR URL or number and produce a structured Chinese code review. Supports standard review, exploratory review with `--explore`, ops review with `--ops` or ops/gitops/moi-gitops/moi-op/ob-ops repos, and issue/design-context review with `--with-issue`. Use for `review pr`, `/review-pr`, `代码审查`, or `看下这个 PR`."
---

# Review PR

Perform evidence-backed PR review in Chinese. Lead with concrete findings, not a summary.

## Modes

- Standard: production-oriented code quality, tests, performance, safety, and prompt quality.
- Explore: demo/PoC review focused on approach, consistency, observability, and iteration.
- Ops: infrastructure/deployment review focused on resources, security, rollout, and environment impact.

Choose `--explore` and `--ops` explicitly when present. Auto-use Ops for `ops`, `gitops`, `moi-gitops`, `moi-op`, and `ob-ops`.

## Standard Deep Switches

In standard mode, expand these sections only when triggered:

- Architecture review: new >=3 source files, major file split/refactor, title/body mentions refactor/restructure/重构/拆分, or type definitions are newly added/substantially rewritten.
- Existing compatibility impact: exported functions/types removed or signatures changed, JSON tags removed/renamed, form/template/config field IDs changed, PR mentions compatibility/migration/存量, or deletions >500.

## Workflow

1. Resolve owner/repo and PR number.
2. Fetch metadata with `gh pr view`: title, body, files, commits, additions, deletions, base/head refs, labels, state, author.
3. Extract design context. Always inspect PR body for design links or inline方案; fetch linked issues/comments when referenced or when `--with-issue` is present; inspect PR comments for maintainer design notes when useful.
4. Read the diff selectively with `gh pr diff`; skip generated files unless behavior changes. Use file-boundary grep and targeted `sed -n` for large PRs.
5. Determine mode and read the matching checklist:
   - `references/standard-checklist.md`
   - `references/explore-checklist.md`
   - `references/ops-checklist.md`
6. In standard mode, also read:
   - always: `references/section-testing.md`, `references/section-risks.md`
   - when deep switches trigger: `references/section-architecture.md`
7. Produce a structured review with severity levels:
   - 🔴 must fix
   - 🟡 should fix
   - 🟢 optional
8. Number findings as `I-N`, not `#N`, to avoid accidental GitHub issue links. Use anchors like `<a id="issue-1"></a>`.
9. Archive to `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`, rotating existing files with `_bakNNN`.
10. Minimize prior review comments from the current user when they match the review-report signature.
11. Post the new review as a PR comment.

## Review Standard

Each finding needs file/line evidence, behavioral impact, and a practical fix. Findings may come from code, design, tests, compatibility, rollout, permissions, or ops risk. If no serious issue is found, say so and mention residual test or rollout risk.
