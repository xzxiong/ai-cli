---
name: review-pr
description: Review GitHub pull requests from a PR URL or PR number and produce a structured, evidence-backed code review. Use when the user asks to "review pr", "code review", "review #123", "审查 PR", "代码审查", or requests an exploratory/demo/PoC review. Support two modes: standard review for production-oriented changes and explore review for demos or experiments; include linked issue context only when the user explicitly asks.
---

# Review PR

Review PRs with a bias toward actionable findings, concrete evidence, and the smallest set of high-signal comments.

## Workflow

1. Resolve the repo and PR number from the user input.
2. Choose review mode:
   - Use `explore` when the user says `--explore`, "探索性 review", "demo review", or "PoC review".
   - Otherwise use `standard`.
3. Gather metadata with `gh pr view`.
4. Read the diff selectively with `gh pr diff`.
5. If the repo exists locally, fetch the PR branch or compare base/head locally to inspect surrounding context, touched call sites, and tests.
6. If the user explicitly asks for linked-issue context, fetch the linked issue and relevant comments.
7. Review against the checklist in `references/checklists.md`.
8. Return only evidence-backed findings, ordered by severity and user impact.

## Gather Context

Use `gh` first because it gives a fast summary of the PR:

```bash
gh pr view <PR> --json number,title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,files,commits,labels
gh pr diff <PR>
```

Prefer local repository context when available:
- Check whether the current directory or a nearby directory is the target repo.
- If available, inspect the full changed files, not just the diff hunk.
- Read neighboring code, tests, configs, and interfaces that the diff depends on.
- Skip generated, vendored, or lock files unless they hide a real behavioral change.

Fetch linked issue context only when the user explicitly requests it, for example with `--with-issue` or "关联 Issue 一起看".

## Review Rules

- Prefer correctness, regressions, and hidden operational risk over style nitpicks.
- Do not invent problems; every finding should point to a concrete file, behavior, or missing safeguard.
- Explain why the issue matters, when it triggers, and how to fix or de-risk it.
- Call out missing tests when the change adds meaningful behavior or risk.
- If the diff is too large to inspect exhaustively, say what you sampled and where uncertainty remains.
- If there are no material issues, say so clearly and mention what you checked.

## Output Shape

Use a compact structure:
1. One-line summary of the PR.
2. `Findings` section with only high-signal issues.
3. `Open Questions` only when something cannot be verified from the code.
4. `Notes` for non-blocking observations, missing tests, or good changes worth highlighting.

For each finding, include:
- severity
- file or symbol
- triggering scenario
- impact
- concrete suggestion

## Optional Actions

If the user asks for a review comment, draft it in Markdown first.
Only post with `gh pr comment` after the user explicitly asks to publish it.

## Reference

Use `references/checklists.md` for mode-specific review priorities and report heuristics.
