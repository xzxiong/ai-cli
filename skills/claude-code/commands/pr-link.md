# PR Link

Output the GitHub PR URL.

## Behavior

- No arguments: find the open PR for the current git branch
- With PR number as argument: output the URL for that specific PR
- Supports both fork workflow (PRs against upstream) and single-repo workflow (PRs against origin)

## Steps

1. Detect the PR target repo:
   - If `upstream` remote exists and points to `matrixorigin/matrixflow`, we are in a **fork workflow** → use `--repo matrixorigin/matrixflow`
   - Otherwise we are in a **one-repo workflow** → omit `--repo` (origin is the target)

   ```bash
   # Check if upstream points to matrixorigin/matrixflow (fork workflow)
   if git remote get-url upstream 2>/dev/null | grep -qE '(github\.com[/:])matrixorigin/matrixflow'; then
     REPO_FLAG="--repo matrixorigin/matrixflow"
   else
     REPO_FLAG=""
   fi
   ```

2. If args provided and is a number:
   ```bash
   gh pr view <number> $REPO_FLAG --json url --jq '.url'
   ```

3. If no args, find PR for current branch:
   ```bash
   gh pr view $REPO_FLAG --json url --jq '.url'
   ```

4. If no PR found, report that no open PR exists for this branch.

5. Output the URL directly — nothing else.
