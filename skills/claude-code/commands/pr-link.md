# PR Link

Output the GitHub PR URL.

## Behavior

- No arguments: find the open PR for the current git branch
- With PR number as argument: output the URL for that specific PR

## Steps

1. If args provided and is a number:
   ```bash
   gh pr view <number> --json url --jq '.url'
   ```

2. If no args, find PR for current branch:
   ```bash
   gh pr view --json url --jq '.url'
   ```

3. If no PR found, report that no open PR exists for this branch.

4. Output the URL directly — nothing else.
