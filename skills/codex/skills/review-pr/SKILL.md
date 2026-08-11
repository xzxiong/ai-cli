---
name: review-pr
description: "Review GitHub pull requests from a PR URL or number and produce a structured Chinese review. Supports standard code review, pure design/docs review with `--design`/`--design-only` or design-only PRs, exploratory review with `--explore`, ops review with `--ops` or ops/gitops/moi-gitops/moi-op/ob-ops repos, and issue/design-context review with `--with-issue`. Use for `review pr`, `/review-pr`, `代码审查`, `设计评审`, `纯设计 review`, or `看下这个 PR`."
---

# Review PR

Perform evidence-backed PR review in Chinese. Select the review mode before writing the report, and lead with concrete findings, not generic summary.

## Modes

- Standard: production-oriented code quality, tests, performance, safety, and prompt quality.
- Design: pure design/docs/spec/RFC review focused on proposal correctness, contract completeness, assumptions, rollout, and implementation readiness. Review the design artifact itself; do not turn it into a file-by-file code review.
- Explore: demo/PoC review focused on approach, consistency, observability, and iteration.
- Ops: infrastructure/deployment review focused on resources, security, rollout, and environment impact.

Choose `--design`/`--design-only`, `--explore`, and `--ops` explicitly when present. Auto-use Ops for `ops`, `gitops`, `moi-gitops`, `moi-op`, and `ob-ops`.

Auto-use Design when all are true:

- The PR changes only design/spec/RFC/documentation artifacts, such as `docs/design/**`, `docs/**.md`, `**/docs/**/*.md`, ADRs, RFCs, or similar proposal files.
- The PR title, body, labels, or changed paths indicate design/docs/spec/architecture/方案 intent.
- The diff does not change runtime source, tests, migrations, proto/OpenAPI/schema sources, generated contracts, workflow/deploy config, or other files that can alter behavior.

Do not use Design for PoC code with docs; use Explore. Do not use Design for implementation PRs that reference a design doc; use Standard and treat the design as context.

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
   - `references/design-checklist.md`
   - `references/explore-checklist.md`
   - `references/ops-checklist.md`
6. In standard mode, also read:
   - always: `references/section-testing.md`, `references/section-risks.md`
   - when deep switches trigger: `references/section-architecture.md`
7. Produce a structured review with severity levels:
   - 🔴 must fix
   - 🟡 should fix
   - 🟢 optional
8. Start the report body with `<!-- codex-review-pr-report -->`, then number findings as `I-N`, not `#N`, to avoid accidental GitHub issue links. Use anchors like `<a id="issue-1"></a>`.
9. Archive to `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`, rotating existing files with `_bakNNN`.
10. Before posting a new round, collapse older full review reports from the current GitHub user:
   - Identify comments/reviews with the `<!-- codex-review-pr-report -->` signature.
   - For legacy reports without the signature, only match comments that clearly look like this skill's full report from the same user, such as structured severity labels plus `I-N` findings or issue anchors.
   - Use GitHub GraphQL `minimizeComment` with classifier `OUTDATED` for each matching, unminimized report. Do not hide inline review discussions, other reviewers' comments, or non-report comments.
11. Post the new full report as a PR issue comment and capture its URL:
   - `jq -Rs '{body: .}' <report-file> | gh api --method POST repos/<owner>/<repo>/issues/<number>/comments --input - --jq .html_url`
   - Do not use `-f body=@<report-file>` or `-F body=@<report-file>` with `gh api`; those form-field flags can post the literal path string instead of the file contents.
12. Submit the PR review state according to the result:
   - In Design mode, post the full report as a PR comment only by default, then skip the remaining review-state bullets unless the user explicitly asks for a GitHub review state. Do not submit `Approve` or `Request changes` merely because the design report says "建议合并" or has no code findings.
   - In Standard, Explore, and Ops modes, use the following rules.
   - If the report contains any 🔴 must fix finding, submit `Request changes` with `gh pr review <number-or-url> --request-changes --body "本轮 review 有必须解决的问题，详见最新报告：<comment-url>"`.
   - If the report recommends merge/approval and has no 🔴 must fix finding, submit `Approve` with `gh pr review <number-or-url> --approve --body "本轮 review 建议合并，详见最新报告：<comment-url>"`.
   - If neither condition applies, leave the detailed PR comment without approving or requesting changes unless the user explicitly asks for a different review state.

## Review Standard

Each finding needs file/line evidence when possible, behavioral or implementation impact, and a practical fix. Findings may come from code, design, tests, compatibility, rollout, permissions, or ops risk. In Design mode, cite document sections/paths/lines and supporting repo evidence instead of creating a "代码审查（逐文件）" section. If no serious issue is found, say so and mention residual implementation, validation, or rollout risk.
