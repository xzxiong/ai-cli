Create or re-analyze a BVT bug issue with CI log analysis.

This command is a thin entry into **new-issue → BVT scenario**.

## Required reads (in order)

1. `~/.claude/skills/new-issue/SKILL.md` (or `~/.codex/skills/new-issue/SKILL.md`)
2. `~/.claude/skills/new-issue/references/scenario-bvt.md` — **only this scenario**

Do not load other `scenario-*.md` files.

## Input

`$ARGUMENTS` = bug description ± CI URL, or `reanalyze #<number>` / `重新分析 #<number>`.

## Process

1. **New**: extract test case + failure + CI URL → create issue immediately → return URL → tiered analysis → gist + comment.
2. **Re-analyze**: fetch issue, extract CI URL, analyze, comment only.
3. Labels if present: `kind/bug-moi`, `kind/bug`, `bvt-tag-issue`; assignee `xzxiong`; then `apply-matrixone-defaults.sh --type bug`.
4. Body: full core-six template in `scenario-bvt.md` (not a one-line stub).
5. Temp `/tmp/bvt-analysis-<run-id>/`; clean up after.

## Title

`[MOI BUG]: <≤60 chars>`
