---
name: review-pr
description: "Review GitHub pull requests from a PR URL or number and produce a structured Chinese review. Supports fast static review without running tests via `--fast`, standard code review, pure design/docs review with `--design`/`--design-only` or design-only PRs, exploratory review with `--explore`, ops review with `--ops` or ops/gitops/moi-gitops/moi-op/ob-ops repos, and issue/design-context review with `--with-issue`. Use for `review pr`, `/review-pr`, `fast review`, `代码审查`, `设计评审`, `纯设计 review`, or `看下这个 PR`."
---

# Review PR

Perform evidence-backed PR review in Chinese. Select the review mode before writing the report, and lead with concrete findings, not generic summary.

## Modes

- Standard: production-oriented code quality, tests, performance, safety, and prompt quality.
- Fast: high-signal static review for quick feedback. Do not run tests, trigger or retry CI, wait for test results, or load the full test-plan checklist. Review the diff and necessary surrounding code for concrete correctness, security, compatibility, and configuration risks. Test files may be read as code context, but the report must state that tests were not executed and must not claim test validation.
- Design: pure design/docs/spec/RFC review focused on proposal correctness, contract completeness, assumptions, rollout, and implementation readiness. Review the design artifact itself; do not turn it into a file-by-file code review.
- Explore: demo/PoC review focused on approach, consistency, observability, and iteration.
- Ops: infrastructure/deployment review focused on resources, security, rollout, and environment impact.

Choose `--fast`, `--design`/`--design-only`, `--explore`, and `--ops` explicitly when present. `--fast` selects Fast and takes precedence over automatic mode detection. Do not combine `--fast` with `--design`, `--design-only`, `--explore`, or `--ops`; ask the user to choose one mode when flags conflict. Auto-use Ops for `ops`, `gitops`, `moi-gitops`, `moi-op`, and `ob-ops`.

Auto-use Design when all are true:

- The PR changes only design/spec/RFC/documentation artifacts, such as `docs/design/**`, `docs/**.md`, `**/docs/**/*.md`, ADRs, RFCs, or similar proposal files.
- The PR title, body, labels, or changed paths indicate design/docs/spec/architecture/方案 intent.
- The diff does not change runtime source, tests, migrations, proto/OpenAPI/schema sources, generated contracts, workflow/deploy config, or other files that can alter behavior.

Do not use Design for PoC code with docs; use Explore. Do not use Design for implementation PRs that reference a design doc; use Standard and treat the design as context.

## Standard Deep Switches

In standard mode, expand these sections only when triggered:

- Architecture review: new >=3 source files, major file split/refactor, title/body mentions refactor/restructure/重构/拆分, or type definitions are newly added/substantially rewritten.
- Existing compatibility impact: exported functions/types removed or signatures changed, JSON tags removed/renamed, form/template/config field IDs changed, PR mentions compatibility/migration/存量, or deletions >500.

## Non-Negotiable Rule: New Runtime Configuration

When a PR adds a runtime configuration item (including Helm values, deployment YAML, environment variables, `Pulumi.*.yaml` keys, ConfigMap/Secret references, feature flags, and application config), review the **configuration file itself** for an adjacent, durable explanation. The PR body, issue, code comment, or a separate document does not substitute for this explanation.

For every new item, the configuration file must make both of these facts explicit:

1. **Kubernetes-effective values**: state the valid values or range in the target Kubernetes environment, plus the applicable cluster/unit/namespace or resource preconditions when they affect validity. Explain the operational effect of each meaningful value. For environment-dependent values, name the relevant K8s fact that makes the value valid, such as an existing `StorageClass`, node label/taint, allocatable CPU or memory, namespace, Service port, or available replica capacity. Do not accept vague wording such as "set as needed" or an unqualified generic default.
2. **Paired configuration**: state whether the item must be used with another configuration item. When it is paired, name the counterpart's exact location as `<file path>:<key>` (and the values precedence/source when relevant), describe the required relationship or compatible value combination, and say what breaks if the counterpart is absent or inconsistent. When it is not paired, explicitly mark it as independent.

Treat a missing, ambiguous, or stale explanation for either requirement as a **🔴 must-fix finding**. Trace value resolution through chart defaults, base values, environment/stack overlays, templates, and generated K8s manifests before deciding that a value is effective. In pure Design mode, do not require an implementation configuration file, but require the design to specify these two requirements for the eventual configuration change.

## Workflow

1. Resolve owner/repo and PR number.
2. Fetch metadata with `gh pr view`: title, body, files, commits, additions, deletions, base/head refs, labels, state, author.
3. Extract design context. Always inspect PR body for design links or inline方案; fetch linked issues/comments when referenced or when `--with-issue` is present; inspect PR comments for maintainer design notes when useful.
4. Read the diff selectively with `gh pr diff`; skip generated files unless behavior changes. For every new runtime configuration item, trace its value from source configuration through overlays/templates to the rendered or consumed K8s resource, and verify the mandatory configuration-file explanation. Use file-boundary grep and targeted `sed -n` for large PRs.
5. Determine mode and read the matching checklist:
   - `references/fast-checklist.md`
   - `references/standard-checklist.md`
   - `references/design-checklist.md`
   - `references/explore-checklist.md`
   - `references/ops-checklist.md`
6. In Standard mode, also read:
   - always: `references/section-testing.md`, `references/section-risks.md`
   - when deep switches trigger: `references/section-architecture.md`
   In Fast mode, do not execute test commands, trigger/retry CI, wait for test results, or read `references/section-testing.md`. Use only `references/fast-checklist.md`; it already requires a visible "tests not executed" limitation in the report.
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
   - In Fast, Standard, Explore, and Ops modes, use the following rules. In Fast mode, any approval recommendation must explicitly say that it is based on static review and that tests were not executed.
   - Idempotency for **all** review states (`Approve`, `Request changes`, and comment-only review): before any `gh pr review` call or retry, query existing reviews for the current user on the current head SHA. If the same decision state already exists on that SHA, do **not** submit another identical review. Only resubmit when the intended decision itself changed. Do not retry just because the comment step printed `ok commented` or because `gh pr review` lacked a similarly loud success line; the report comment and the review decision are separate API calls.
   - If the report contains any 🔴 must fix finding, submit `Request changes` with `gh pr review <number-or-url> --request-changes --body "本轮 review 有必须解决的问题，详见最新报告：<comment-url>"`.
   - If the report recommends merge/approval and has no 🔴 must fix finding, submit `Approve` with `gh pr review <number-or-url> --approve --body "本轮 review 建议合并，详见最新报告：<comment-url>"`.
   - If neither condition applies, leave the detailed PR comment without approving or requesting changes unless the user explicitly asks for a different review state.

## Review Standard

Each finding needs file/line evidence when possible, behavioral or implementation impact, and a practical fix. Findings may come from code, design, tests, compatibility, rollout, permissions, or ops risk. In Design mode, cite document sections/paths/lines and supporting repo evidence instead of creating a "代码审查（逐文件）" section. If no serious issue is found, say so and mention residual implementation, validation, or rollout risk.
