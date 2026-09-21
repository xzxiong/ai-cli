Create a CI failure issue from a GitHub Actions URL.

This command is a thin entry into **new-issue → CI scenario**.

## Required reads (in order)

1. `~/.claude/skills/new-issue/SKILL.md` (or `~/.codex/skills/new-issue/SKILL.md`)
2. `~/.claude/skills/new-issue/references/scenario-ci.md` — **only this scenario**

Do not load other `scenario-*.md` files.

## Input

`$ARGUMENTS` = Actions run or job URL (default repo `matrixorigin/matrixflow`).

## Process

1. Follow `scenario-ci.md`: metadata → tiered logs/artifacts → classify → dedup → create issue with core-six body.
2. Run `apply-matrixone-defaults.sh --repo ... --issue ... --type bug`.
3. Add labels `kind/bug-moi`, `kind/bug` if they exist; assignee `xzxiong` unless overridden.
4. Upload useful logs to gist; post analysis comment (≤60KB).
5. Temp `/tmp/ci-issue-<run-id>/`; clean up after.

## Title

`[CI BUG]: <workflow-name> - <failure-summary>`
