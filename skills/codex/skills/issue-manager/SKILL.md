---
name: issue-manager
description: Create structured GitHub issues from text, break parent issues into sub-issues, or link existing issues as sub-issues. Use for `/issue-manager`, issue breakdown, task issue creation, or sub-issue linking.
---

# Issue Manager

Create and organize GitHub issues with structured bodies and sub-issue links.

## Modes

- `create --from-text ... --title ...`: turn discussion or requirements into a structured issue.
- `breakdown --parent <number> [--body-format simple|tasklist|none]`: create sub-issues from a parent checklist.
- `link --parent <number> --children <n1,n2,...> [--update-body]`: link existing issues as sub-issues.

## Workflow

1. Resolve the repo from the current GitHub context or explicit input.
2. For create mode, extract background, goal, technical approach, tasks, and priority.
3. For breakdown mode, fetch the parent issue body and extract unchecked checklist items.
4. Create child issues with clear titles and actionable bodies:
   - `## 目标`
   - `## 技术细节`
   - `## 验证标准`
   - `## 关联`
5. Use GitHub GraphQL `addSubIssue` for parent-child links; fetch node IDs for parent and children before linking.
6. Optionally update the parent body using the requested body format.

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
