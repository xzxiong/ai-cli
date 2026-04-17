# PR Description Template

Use this file after reading `SKILL.md`.
Mirror the language already used by the PR when possible. The sample below uses Chinese headings because that is the most common target format for this workflow.

## Preserve Links

Before drafting the new body:
- Extract the existing `## 相关链接` or `## Related Links` section.
- Keep everything in that section verbatim until the next level-2 heading or end of file.
- If neither section exists, use the default placeholder block from the template.
- Never discard author-supplied issue references such as `Fixes #123`, design docs, or API docs.

## Diagram Selection

Choose at most one of these blocks:
- Use `调用链` when the PR mainly changes one module or package and the key insight is function flow.
- Use `数据流` when the PR spans API, service, storage, jobs, or multiple modules.
- Omit the block when the change is trivial, mostly config, or easy to understand without a diagram.

Keep diagrams short and mark changed points with `← NEW` or `← 修改`.

## Checkbox Heuristics

Only check an item when there is clear evidence in the diff or the user explicitly confirms it.

- `新功能`: new user-visible or API-visible capability
- `缺陷修复`: bug fix with no intentional breaking behavior
- `破坏性变更`: incompatible API, schema, config, or behavior change
- `单元测试已添加/更新`: tests added or modified in the PR
- `集成测试已通过` / `手动测试已完成` / `性能测试已进行`: only if the PR body already says so or the user confirms it
- 文档项: only if docs, README, API specs, SDK docs, or changelog changed
- `截图`: keep for frontend/UI changes; otherwise leave empty or omit if the surrounding repo convention allows it

## Suggested Template

```markdown
## 变更说明

[用 2-4 句话概括背景、目标和整体改动。]

- 变更点 1：一句话说明做了什么、为什么重要
- 变更点 2：一句话说明影响范围或使用方式
- 变更点 3：一句话说明验证、兼容性或后续注意点

### 核心变更

**1. [模块/功能名]**
- 具体改动点
- 关键影响或使用方式

**2. [模块/功能名]**
- 具体改动点

### 调用链 / 数据流
<!-- 二选一；简单改动可省略 -->

### 新增文件
| 文件 | 说明 |
|------|------|
| `path/to/file.go` | 一句话说明 |

## 变更类型
- [ ] 新功能（向后兼容）
- [ ] 缺陷修复（向后兼容）
- [ ] 破坏性变更（需要迁移指南）

## 影响范围
### 影响的团队
- [ ] 平台组
- [ ] 应用后端组
- [ ] 应用前端组
- [ ] 架构组

### 测试验证
- [ ] 单元测试已添加/更新
- [ ] 集成测试已通过
- [ ] 手动测试已完成
- [ ] 性能测试已进行
- [ ] Issue 修复已补充稳定复现测试

### 文档更新
- [ ] API/SDK 文档已更新
- [ ] 用户文档已更新
- [ ] README 已更新
- [ ] CHANGELOG 已更新

## 环境验证
| 环境 | 状态 | 备注 |
|------|------|------|
| 本地开发 | [ ] |  |
| 测试环境 | [ ] |  |
| 预发环境 | [ ] |  |

## 相关链接
- GitHub Issue: （使用 `Fixes #123` 或 `Closes #123`）
- 设计文档: [链接]
- API 文档: [链接]

## 截图（前端必填）

## 检查清单
- [ ] 代码已自测
- [ ] 提交信息规范
- [ ] 无调试代码
- [ ] 遵循编码规范
- [ ] 已同步上游最新代码
```

## Output Quality Bar

- Prefer a compact, accurate description over a long generic one.
- Avoid repeating the file list when the narrative already explains the change.
- If validation or rollout status is unknown, leave the checkbox unchecked instead of guessing.
- If the PR is exploratory, make that explicit in the summary rather than pretending it is production-ready.
