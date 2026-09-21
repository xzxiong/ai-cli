---
name: ci-issue
description: Analyze MatrixFlow GitHub Actions CI failures (Moi-Core, lint/doc/unit/integration, timeout/OOM/LOAD evidence) and create a structured issue. Use for `/ci-issue`, "ci issue", "new ci issue", or an Actions run/job URL that should become an issue. Delegates body quality and MatrixOrigin defaults to new-issue scenario-ci.
---

# CI Issue

Thin entry point into **new-issue → CI scenario**.

## Required reads

1. `../new-issue/SKILL.md` — router, quality bar, create + MatrixOrigin defaults  
2. `../new-issue/references/scenario-ci.md` — **only** CI analysis tiers, ports, resource rules, body template  

Do **not** load other `scenario-*.md` files.

## Behavior

1. Input: GitHub Actions run or job URL (default repo `matrixorigin/matrixflow`).
2. Follow `scenario-ci.md` end-to-end: metadata → tiered logs → classify → dedup → create issue → `apply-matrixone-defaults.sh --type bug` → gist + analysis comment when useful.
3. `/ci-issue` implies **create + comment** (external writes allowed). If the user only asks for analysis, report without creating.
4. Assignee default `xzxiong` when creating unless overridden; labels `kind/bug-moi`, `kind/bug` only if they exist.
5. Temp: `/tmp/ci-issue-<run-id>/`; clean up after post.

## Resolve helper

```bash
for c in \
  "$(dirname "$0")/../new-issue/scripts/apply-matrixone-defaults.sh" \
  /data2/xzxiong/.claude/skills/new-issue/scripts/apply-matrixone-defaults.sh \
  /data2/xzxiong/.codex/skills/new-issue/scripts/apply-matrixone-defaults.sh
do
  [[ -x "$c" ]] && helper="$c" && break
done
```

## Out of scope

- BVT product pytest + `bvt-tag-issue` → use **bvt-issue** / `scenario-bvt.md`
- Long-term runner capacity redesign without a failing run → **new-issue** infra scenario  
