---
name: merge-main
description: "Merge an upstream branch into the current branch and resolve conflicts end to end. Auto-detect MatrixFlow/moi-* repositories as dev-based and other repositories as main-based. Use for `merge main`, `merge dev`, `合并 main`, `合并 dev`, `resolve conflicts`, `解决冲突`, `update from main/dev`, or rebase requests."
---

# Merge Main

Merge the target branch into the current branch, resolve conflicts, adapt downstream callers/tests/tools, and verify the result.

## Defaults

- If the user specifies a branch, use it.
- Otherwise detect the target branch:
  - remote URL contains `matrixflow` or `/moi-` -> `dev`
  - all other repos -> `main`
- Support `--rebase` only when explicitly requested.

## Workflow

1. Precheck the repo:
   - `git status --porcelain`
   - `git branch --show-current`
   - `git remote -v`
   - if there are unrelated local changes, do not overwrite them.
2. Fetch the chosen upstream remote and target branch.
3. Run `git merge <remote>/<branch>` or `git rebase <remote>/<branch>`.
4. If conflicts occur, list them with `git diff --name-only --diff-filter=U`.
5. Resolve conflicts by priority:
   - interfaces, types, and function signatures
   - implementations and stores
   - handlers, routes, and config
   - tests, mocks, fixtures, and E2E helpers
   - CI, Dockerfiles, scripts, and generated files
6. For signature/type/interface changes, search callers and update non-conflict files affected by the merge.
7. Validate with the repo's normal build/test commands. For Go repos, prefer:
   - `go build ./...`
   - `go vet ./...`
   - targeted `go test` first, broader tests when risk warrants it
8. Complete the merge or rebase. Before staging, inspect `git status` and avoid adding unrelated local config such as `.claude/`, `.mcp.json`, or IDE files.
9. Report merged branch, conflicts resolved, additional adaptations, and verification status.

## Conflict Rules

- Understand both sides before editing: HEAD is current branch; theirs is the target branch.
- Preserve both functional intents unless they truly conflict.
- Do not stop at deleting conflict markers. Check callers, mocks, test helpers, E2E harnesses, config, and tools.
- For `go.mod`/`go.sum`, prefer the target branch direction, then run the module tidy command appropriate for the repo.
- For generated files, prefer regenerating or taking the target version; avoid hand-merging generated output.

## Resources

Read `references/conflict-checklist.md` when conflicts exist or the merge touches interfaces, stores, handlers, tests, CI, or generated files.
