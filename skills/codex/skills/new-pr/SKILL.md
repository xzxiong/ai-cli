---
name: new-pr
description: Create a new branch from current local changes, commit, push, open a PR, update its description, and optionally run code review. Use for `new pr`, `开 PR`, `提 PR`, `create/open/submit PR`, `推个 PR`, or `/new-pr`.
---

# New PR

Create a PR from current local changes.

## Workflow

1. Confirm the current directory is a Git repo and there are local changes.
2. Parse input: commit message plus optional `--base <branch>`, `--branch <name>`, and `--no-review`.
3. Detect fork vs same-repo mode from remotes:
   - Fork mode if both `xzxiong/<repo>` and `matrixorigin/<repo>` remotes exist.
   - Same-repo mode otherwise; `matrixone-operator` is always same-repo mode.
4. Choose base branch: `dev` for `matrixflow`/`moi-frontend`; otherwise `main` or `master`, unless overridden.
5. Create or switch to the requested/new branch.
6. Stage and commit changes.
7. Push to the correct remote.
8. Create or reuse an open PR.
9. Update PR description and run review unless `--no-review` is set.

## Safety

- Do not create PRs directly from `main`, `master`, or `dev` without a new feature branch.
- Do not overwrite user changes or existing branches without confirmation.
