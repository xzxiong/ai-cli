---
name: review-fix
description: Fix unresolved GitHub PR review comments, commit changes, push, and reply to review threads. Use for `/review-fix`, requests to address PR review comments, or fix comments on a PR.
---

# Review Fix

Apply code fixes requested by PR review comments.

## Workflow

1. Resolve PR URL or number and confirm the local branch matches the PR head branch.
2. Inspect workspace state:
   - If uncommitted changes already exist, treat them as candidate fixes and proceed carefully.
   - If clean, fetch unresolved review threads.
3. Fetch review threads with GraphQL, including `isResolved`, `isOutdated`, path, line/startLine, and every comment id/author/body.
4. Default to unresolved-only; skip outdated threads and pure discussion such as LGTM or clarification-only comments.
5. Group actionable comments by file and inspect surrounding code.
6. Apply minimal fixes that match reviewer intent; use GitHub suggestion blocks directly when safe.
7. Run relevant validation such as `go vet`, tests, or syntax checks.
8. Commit and push with a message like `fix: address review comments on PR #<number>`.
9. Reply to handled review threads with GraphQL `addPullRequestReviewThreadReply`, including the fixing commit SHA.

## Rules

- Keep fixes scoped to reviewer comments.
- Ask before applying risky or ambiguous requested changes.
- Process very large comment sets in batches.
- If there are more than 20 actionable comments, process in batches and report progress.
