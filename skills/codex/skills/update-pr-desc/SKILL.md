---
name: update-pr-desc
description: Generate and update a structured GitHub PR description from actual code changes, commits, files, and existing PR body. Use for `/update-pr-desc`, `update pr desc`, `refresh PR description`, `rewrite PR body`, or `根据代码更新 PR 描述`.
---

# Update PR Description

Rewrite PR descriptions from the real diff, preserving manually maintained links.

## Workflow

1. Resolve the PR URL/number and repository.
2. Fetch PR metadata: title, body, files, commits, additions/deletions, base/head, labels, and state.
3. Read the diff selectively; focus on business logic, handlers, models, repositories, types, routes, and meaningful config.
4. Skip generated files such as `swagger.json` and `docs.go` unless they indicate behavior change.
5. Fetch linked issue context when present.
6. Generate a Chinese PR body with:
   - Change summary.
   - Core changes grouped by module.
   - Data flow or call chain when useful.
   - Added/modified file table.
   - Change type and impact.
   - UT/BVT coverage when tests are present.
   - Preserved `## 相关链接` or `## Related Links` from the old body verbatim.
7. Update via GitHub REST API, not `gh pr edit --body`.
8. Verify the updated body with `gh pr view`.

## Rule

Do not invent behavior from the title alone; every claim should be supported by diff, commits, or linked issue context.
