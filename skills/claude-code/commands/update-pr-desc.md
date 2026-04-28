根据 PR 的实际代码变更，自动生成结构化的 PR 描述并更新到 GitHub。

参数: $ARGUMENTS (PR URL 或 PR 编号)

## 步骤

### 1. 获取 PR 元数据
```bash
gh pr view <PR_NUMBER> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state
```
提取：PR 标题、分支名、文件列表、commit 列表、关联 issue。

### 2. 获取代码 diff
```bash
gh pr diff <PR_NUMBER> 2>&1 | grep -n '^diff --git'
```
按需用 `sed -n '<START>,<END>p'` 读取核心文件 diff。

重点关注：业务代码（handler、model、repo、types）、路由注册、功能性修改。
跳过：自动生成文件（swagger.json、docs.go 等）。

### 3. 获取关联 Issue（如有）
```bash
gh issue view <ISSUE_NUMBER> --json title,body
```

### 4. 生成描述

按以下模板生成，根据 diff 智能填充：

- **变更说明**：~100字概述 + 关键变更点列表
- **核心变更**：按模块分组（API、集成逻辑、数据层、文档等）
- **调用链/数据流**：单模块→函数调用链；跨模块→模块间数据流（ASCII 图，用 `← NEW` / `← 修改` 标注）；简单变更可省略
- **新增/修改文件表格**
- **变更类型**：根据实际变更勾选
- **影响范围**：根据实际变更勾选团队、测试、文档状态
- **相关链接**：从原始 PR body 中原样保留 `## 相关链接` 部分，不要覆盖

### 5. 更新 PR 描述

⚠️ 不要用 `gh pr edit --body`（Projects Classic 会导致静默失败），用 REST API：
```bash
cat > /tmp/pr-body.md << 'PREOF'
...生成的描述...
PREOF
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER> -X PATCH -F "body=@/tmp/pr-body.md"
rm /tmp/pr-body.md
```

### 6. 验证
```bash
gh pr view <PR_NUMBER> --json body --jq '.body' | head -5
```

## PR 描述模板

```markdown
## 变更说明

[~100字概述]

- 变更点 1
- 变更点 2

### 核心变更

**1. [模块名]**
- 具体改动

### 调用链 / 数据流
<!-- 单模块：函数调用链；跨模块：模块间数据流 -->

### 新增文件
| 文件 | 说明 |
|------|------|
| `path/file` | 说明 |

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
- [ ] **Issue修复必填**（moi内核团队）：已添加能够100%复现Issue的BVT测试或单元测试

### 文档更新
- [ ] API/SDK文档已更新
- [ ] 用户文档已更新
- [ ] README已更新
- [ ] CHANGELOG已更新

## 环境验证
| 环境 | 状态 | 备注 |
|------|------|------|
| 本地开发 | [ ] |  |
| 测试环境 | [ ] |  |
| 预发环境 | [ ] |  |

## 相关链接
<!-- ⚠️ 从原始 PR body 原样保留，不要覆盖 -->

## 截图（前端必填）

## 检查清单
- [ ] 代码已自测
- [ ] 提交信息规范
- [ ] 无调试代码
- [ ] 遵循编码规范
- [ ] 已同步上游最新代码
```
