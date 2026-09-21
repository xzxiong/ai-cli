---
name: issue-manager
description: Create structured GitHub issues from text, break parent issues into sub-issues, or link existing issues as sub-issues. Use for `/issue-manager`, issue breakdown, task issue creation, or sub-issue linking. For MatrixOrigin repositories, apply New MatrixOne Intelligence plus Issue Type, Priority, Iteration, 视角=开发实现, and initial Labels after every created issue.
---

# Issue Manager

Create and organize GitHub issues with structured bodies and sub-issue links.

## Modes

- `create --from-text ... --title ...`: turn discussion or requirements into a structured issue.
- `breakdown --parent <number> [--body-format simple|tasklist|none]`: create sub-issues from a parent checklist.
- `link --parent <number> --children <n1,n2,...> [--update-body]`: link existing issues as sub-issues.

## Workflow

1. Resolve the repo from the current GitHub context or explicit input.
2. For create mode, follow [`new-issue`](../new-issue/SKILL.md): classify into one scenario (`references/scenario-*.md` under new-issue), load only that file, and draft 背景/目标/名词解释/事实依据/数据依据/预案/任务/测试方案/验收. Index: `references/body-templates.md`.
3. For breakdown mode, fetch the parent issue body and extract unchecked checklist items.
4. Create child issues with clear titles and actionable bodies (minimum):
   - `## 目标`
   - `## 事实依据` or `## 技术细节` (real paths/config when known)
   - `## 测试方案` / `## 验证标准`
   - `## 关联`
   For non-trivial children, also include `## 名词解释`, `## 数据依据`, and `## 方案（预案）` when the parent has that context.
5. Apply [`new-issue`](../new-issue/SKILL.md) defaults after creating every parent or child issue. This is required for repositories owned by `matrixorigin`.
6. Use GitHub GraphQL `addSubIssue` for parent-child links; fetch node IDs for parent and children before linking.
7. Optionally update the parent body using the requested body format.

## Body Formats

- `simple`: `- [ ] #1234 Description`; best readability.
- `tasklist`: GitHub tasklist block with full URLs; best native progress behavior.
- `none`: leave parent body unchanged and rely on sidebar links.

## Rules

- Do not duplicate existing sub-issues when re-running.
- Preserve manually written parent context.
- Prefer concise issue bodies over copied chat transcripts.
- Break down only when the parent has three or more distinct tasks that can be worked independently.
- If GraphQL sub-issue linking fails due to permissions, report that `gh auth refresh -s write:discussion -s repo` may be needed.
