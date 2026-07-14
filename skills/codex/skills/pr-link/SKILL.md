---
name: pr-link
description: "Print the GitHub pull request URL for the current branch or for a provided PR number, including fork-based PRs whose base repo differs from the local origin. Use when the user asks for `pr link`, `PR URL`, `show/open current PR link`, or wants only the GitHub PR URL without extra explanation."
---

# PR Link

Output the GitHub PR URL directly.

## Behavior

- With a numeric argument, run `gh pr view <number> --repo <base-repo> --json url --jq '.url'`.
- With no argument, find the open PR for the current branch using the repository mode below.
- If no open PR exists for the current branch, say that plainly.

## Repository Mode

First identify:

- `branch`: `git branch --show-current`
- `origin repo`: owner/name parsed from `git remote get-url origin`
- `upstream repo`: owner/name parsed from `git remote get-url upstream`, if present
- `current repo`: `gh repo view --json nameWithOwner,parent --jq '{repo:.nameWithOwner,parent:.parent.nameWithOwner}'`, if needed

Choose `base-repo`:

1. If `upstream repo` exists, use it as `base-repo`.
2. Else if `current repo.parent` exists, use the parent as `base-repo`.
3. Else use `origin repo` as `base-repo`.
4. Special case: if either `origin repo`, `upstream repo`, or `current repo.parent` is `matrixorigin/matrixflow`, set `base-repo=matrixorigin/matrixflow`.

Distinguish modes:

- **One repo mode**: `origin repo == base-repo`. The branch lives in the same repository that owns the PR.
- **Fork repo mode**: `origin repo != base-repo`. The branch lives in a fork, and the PR lives in the base repository.

## Lookup Commands

For one repo mode, prefer:

```bash
gh pr view --repo "$base_repo" --json url --jq '.url'
```

If that does not find a PR, fall back to:

```bash
gh pr list --repo "$base_repo" --head "$branch" --state open --json url --jq '.[0].url // empty'
```

For fork repo mode, do not query the fork repo. Query the base repo with an owner-qualified head:

```bash
head_owner="${origin_repo%%/*}"
gh pr list --repo "$base_repo" --head "$head_owner:$branch" --state open --json url --jq '.[0].url // empty'
```

For `matrixorigin/matrixflow`, always query `--repo matrixorigin/matrixflow` when the local repository is either the upstream repo or a fork of it. In fork mode, use `--head "<fork-owner>:<branch>"`; in one repo mode, use `--head "<branch>"`.

## Output Rule

Print only the URL when found. Do not add summaries, bullets, or surrounding prose.
