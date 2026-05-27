---
name: review-pr-v1
description: Legacy Chinese PR review workflow with standard, exploratory, and ops modes. Use only when the user explicitly asks for `/review-pr-v1` or the old v1 review format.
---

# Review PR V1

Run the legacy PR review format.

## Workflow

1. Resolve PR URL or number.
2. Fetch PR metadata and diff.
3. Select mode:
   - Standard by default.
   - Explore with `--explore`.
   - Ops with `--ops` or ops/gitops-style repos.
4. Generate the v1 report structure:
   - Summary.
   - PR description review.
   - Change overview.
   - Solution and test review.
   - File-by-file code review.
   - API/config changes.
   - Risk checks.
5. Archive under `~/pr_review/`.
6. Minimize previous review comments from the same user.
7. Post the review comment.

Prefer the main `review-pr` skill unless the user asks for v1 explicitly.
