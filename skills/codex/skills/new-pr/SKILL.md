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
   - Iterate all remotes by URL, not by remote name.
   - Fork mode if one remote points to `xzxiong/<repo>` and another to `matrixorigin/<repo>`.
   - Push to the `xzxiong` remote and create PR in `matrixorigin/<repo>` with `--head xzxiong:<branch>`.
   - Same-repo mode otherwise; `matrixone-operator` is always same-repo mode.
4. Choose base branch: `dev` for `matrixflow`/`moi-frontend`; otherwise detect `main` then `master`, unless overridden.
5. Create or switch to the requested/new branch.
   - If no branch is provided and current branch is `main`, `master`, or `dev`, derive `<type>/<summary>` from the commit message, replace spaces with `-`, and truncate around 50 chars.
6. Stage and commit changes.
7. Push to the detected remote.
8. Reuse an existing open PR before creating a new one:
   - fork: `gh pr list --repo <repo> --head xzxiong:<branch> --state open`
   - same-repo: `gh pr list --repo <repo> --head <branch> --state open`
9. Update PR description and run review unless `--no-review` is set.
   - PR description/review must be done by the current agent using `update-pr-desc` and `review-pr` workflows, not delegated.

## Safety

- Do not create PRs directly from `main`, `master`, or `dev` without a new feature branch.
- Do not overwrite user changes or existing branches without confirmation.
- Support both SSH and HTTPS GitHub remote URLs when extracting owner/repo.
