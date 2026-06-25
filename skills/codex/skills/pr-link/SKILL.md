---
name: pr-link
description: "Print the GitHub pull request URL for the current branch or for a provided PR number. Use when the user asks for `pr link`, `PR URL`, `show/open current PR link`, or wants only the GitHub PR URL without extra explanation."
---

# PR Link

Output the GitHub PR URL directly.

## Behavior

- With a numeric argument, run `gh pr view <number> --json url --jq '.url'`.
- With no argument, run `gh pr view --json url --jq '.url'` for the current branch.
- If no open PR exists for the current branch, say that plainly.

## Output Rule

Print only the URL when found. Do not add summaries, bullets, or surrounding prose.
