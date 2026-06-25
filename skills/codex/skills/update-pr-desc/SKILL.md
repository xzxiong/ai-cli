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
   - Change summary around 100 Chinese characters plus key bullets.
   - Core changes grouped by module.
   - Data flow or call chain when useful; use ASCII diagrams with `← NEW` and `← 修改` annotations for non-trivial flow.
   - Added/modified file table.
   - Change type and impact.
   - UT/BVT coverage when tests are present: group by function, list input/mock behavior/expected result, cover happy path, error path, boundary values, concurrency where relevant, and bug-fix regression coverage.
   - Preserved `## 相关链接` or `## Related Links` from the old body verbatim.
   - Frontend screenshots section when frontend changes are present.
7. Update via GitHub REST API, not `gh pr edit --body`, because Projects Classic can cause silent failures.
8. Verify the updated body with `gh pr view`.

## Rule

Do not invent behavior from the title alone; every claim should be supported by diff, commits, or linked issue context.

## Template Sections

Use these sections when applicable:

- `## 变更说明`
- `### 核心变更`
- `### 调用链 / 数据流`
- `### 新增文件`
- `## 变更类型`
- `## 影响范围`
- `### 测试验证`
- `## 环境验证`
- `## 相关链接`
- `## 截图（前端必填）`
- `## 检查清单`
