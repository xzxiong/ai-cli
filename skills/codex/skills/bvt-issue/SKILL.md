---
name: bvt-issue
description: Create or re-analyze a MatrixFlow BVT bug issue with CI log analysis. Use for `/bvt-issue`, "bvt issue", "new bvt issue", BVT pytest failures with optional CI URL, or `reanalyze #N` / 重新分析. Delegates body quality and MatrixOrigin defaults to new-issue scenario-bvt.
---

# BVT Issue

Thin entry point into **new-issue → BVT scenario**.

## Required reads

1. `../new-issue/SKILL.md` — router, quality bar, create + MatrixOrigin defaults  
2. `../new-issue/references/scenario-bvt.md` — **only** BVT modes, tiers, ports, body template  

Do **not** load other `scenario-*.md` files.

## Behavior

1. **New**: extract test node id, failure text, CI URL → create issue immediately (return URL) → tiered analysis → gist + comment.  
2. **Re-analyze**: `reanalyze` / `re-analyze` / `重新分析` + issue number/URL → skip create → analyze → comment.  
3. Defaults: repo `matrixorigin/matrixflow`; labels `kind/bug-moi`, `kind/bug`, `bvt-tag-issue` if present; assignee `xzxiong`; then `apply-matrixone-defaults.sh --type bug`.  
4. Prefer zero extra questions when test name + failure text are present.  
5. Temp: `/tmp/bvt-analysis-<run-id>/`; clean up after post.

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

- Moi-Core unit/integration-only CI without BVT semantics → **ci-issue** / `scenario-ci.md`  
