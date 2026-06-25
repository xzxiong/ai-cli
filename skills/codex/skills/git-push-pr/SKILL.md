---
name: git-push-pr
description: Commit current changes, push a branch, create or reuse a PR, update PR description, and run code review. Use for `/git-push-pr` or requests to do commit → push → PR → description → review in one workflow.
---

# Git Push PR

Complete the current branch PR workflow end to end.

## Workflow

1. Confirm the current directory is a Git repo and the current branch is not `main`, `master`, or `dev`.
2. Inspect `git status --porcelain`.
3. Commit staged/unstaged changes with the provided message; if no changes but unpushed commits exist, continue to push.
4. Detect fork mode:
   - Scan all remote URLs; do not assume names like `origin` or `upstream`.
   - If remotes include both `xzxiong/<repo>` and `matrixorigin/<repo>`, push to the xzxiong remote and open PR against upstream.
   - Otherwise use same-repo mode with `origin`.
   - Treat `matrixone-operator` as same-repo mode.
5. Choose default base: `dev` for `matrixflow` and `moi-frontend`; otherwise `main` or `master`.
6. Push the branch.
7. Reuse an existing open PR for the branch or create one. Use `--head xzxiong:<branch>` in fork mode and `--head <branch>` in same-repo mode.
8. Update the PR description using the `update-pr-desc` workflow.
9. Run PR review using the `review-pr` workflow unless disabled.

## Flags

- `--base <branch>` overrides the base branch.
- `--no-pr` stops after push.
- `--no-review` skips review.

## Push Failure

If push is rejected, report the exact remote/branch and suggest rebasing with `git pull --rebase <remote> <branch>` rather than force-pushing.
