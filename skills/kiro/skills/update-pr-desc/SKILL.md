---
name: update-pr-desc
description: |
  根据 PR 的实际代码变更，自动生成结构化的 PR 描述并直接更新到 GitHub。

  Use this skill when:
  - The user says "update pr desc" followed by a PR URL or number
  - The user invokes `/update-pr-desc <PR_URL>`
---

# Update PR Description Skill

## 目的
根据 PR 的实际代码变更，自动生成结构化的 PR 描述并直接更新到 GitHub。

## 使用方法
```bash
kiro chat "update pr desc https://github.com/matrixorigin/matrixflow/pull/<PR_NUMBER>"
# 或
kiro chat "update pr desc #<PR_NUMBER>"
```

## Skill 逻辑

### 1. 获取 PR 元数据
```bash
gh pr view <PR_NUMBER> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state
```
从中提取：PR 标题、分支名、文件列表、commit 列表、关联 issue。

### 2. 获取代码 diff
```bash
# 查看变更文件列表及 diff 位置索引
gh pr diff <PR_NUMBER> 2>&1 | grep -n '^diff --git'

# 按需读取核心代码变更（跳过生成文件如 swagger/docs）
gh pr diff <PR_NUMBER> 2>&1 | sed -n '<START>,<END>p'
```

重点关注：
- 新增的业务代码文件（handler、model、repo、types）
- 路由注册变更（`Deploy` / `router` 方法）
- 已有文件的功能性修改
- 跳过自动生成文件（swagger.json、docs.go 等）、纯文档文件可快速浏览

### 3. 获取关联 Issue（如有）
```bash
gh issue view <ISSUE_NUMBER> --json title,body
```

### 4. 分析变更并生成描述

根据代码 diff 分析，生成结构化描述，包含：

- **变更说明**：先用约100字概述整体变更背景和目的，再用列表罗列关键变更点（每条一句话，覆盖做了什么、为什么、怎么用）
- **核心变更**：按模块分组（API、集成逻辑、数据层、文档等），每组列出具体改动
- **调用链 / 数据流**：根据变更范围自动选择展示方式（见下方规则）
- **新增/修改文件表格**：关键文件 + 一句话说明
- **变更类型**：勾选对应项（新功能/缺陷修复/破坏性变更）
- **影响范围**：勾选影响的团队、测试验证状态、文档更新状态
- **UT/BVT 覆盖说明**：当 PR 包含测试代码时，按以下维度生成说明（参考 review-pr skill 的测试方案梳理）：
  - **UT**：按函数分组，用表格列出每个测试场景的输入/mock行为/期望结果；覆盖 happy path、error path、边界条件、并发安全
  - **BVT**：说明覆盖的端到端场景和断言内容
  - **回归验证**（Bug Fix PR）：指出哪个测试能在修复前 fail、修复后 pass
  - 如果 PR 无测试代码，在 checklist 中不勾选对应项即可，无需填写说明
- **关联链接**：**保留原有 PR body 中 "## 相关链接" 部分的内容**（见下方规则）

#### ⚠️ 保留原有 "## 相关链接" 规则

生成新描述时，必须从步骤 1 获取的原始 PR body 中提取 `## 相关链接` 部分（从 `## 相关链接` 到下一个 `## ` 标题或文件末尾），**原样保留**到新描述中。

原因：作者在创建 PR 时通常已手动填写了 Issue 链接（`Fixes #123`、`Closes #456`）、设计文档链接等，这些信息无法从 diff 中推断，覆盖会丢失关键关联。

具体做法：
1. 从原始 body 中用正则或文本匹配提取 `## 相关链接` 到下一个 `##` 之间的内容
2. 如果原始 body 中没有 `## 相关链接`，则使用模板中的默认占位符
3. 将提取的内容原样放入新描述的 `## 相关链接` 位置

#### 调用链 / 数据流规则

在"核心变更"之后、"新增文件"之前，根据变更范围添加一个 `### 调用链 / 数据流` 小节：

**判断标准**：
- **单模块修改**（变更文件属于同一个 package/module）→ 展示**函数调用链**
- **跨模块/跨服务修改**（变更涉及多个 package、多个服务、或 API ↔ 业务逻辑 ↔ 数据层）→ 展示**模块/服务间数据流**

**单模块：函数调用链**

用 ASCII 箭头展示修改点在调用链中的位置，标注 `← 本次修改` 或 `← NEW`：

```markdown
### 调用链

\```
process_file_consumer()
  → _start_processing(file_id)
      → crud_file.update_status(PROCESSING)    ← 已有
  → _heartbeat_loop(file_id)                   ← NEW: 心跳协程
      → crud_file.touch_file_updated_at()      ← NEW
  → process_file(job_data)
  → finally: heartbeat_task.cancel()           ← NEW: 清理心跳
\```
```

**跨模块/跨服务：数据流**

用 ASCII 流程图展示模块/服务之间的数据流向，标注修改点：

```markdown
### 数据流

\```
[API Gateway]                    [job-consumer]                    [Database]
     │                                │                                │
     │  POST /parse                   │                                │
     ├───────────────────────────────→│                                │
     │                                │  INSERT file (PENDING)         │
     │                                ├───────────────────────────────→│
     │                                │                                │
     │                                │  UPDATE file (PROCESSING)      │
     │                                ├───────────────────────────────→│
     │                                │                                │
     │                                │  heartbeat: touch updated_at   │  ← NEW
     │                                ├──── every 5min ───────────────→│
     │                                │                                │
     │                                │  cleanup: stale → FAILED       │  ← NEW
     │                                ├──── every 30min ──────────────→│
\```
```

**格式要求**：
- 使用 Markdown 代码块（\`\`\`）包裹，确保等宽字体对齐
- 用 `← NEW` 标注新增的调用/数据流，`← 修改` 标注已有但被修改的部分
- 保持简洁，只展示与本次变更相关的关键路径，不需要画出完整系统架构
- 如果变更非常简单（如仅改配置、仅改文案），可以省略此小节

### 5. 更新 PR 描述

⚠️ `gh pr edit --body` 在仓库启用了 Projects Classic 时会因 deprecation warning 导致失败（exit code 1 但实际未更新）。

正确做法：
```bash
# 将描述写入临时文件
cat > /tmp/pr-body.md << 'EOF'
...生成的描述...
EOF

# 使用 REST API 直接更新（绕过 GraphQL Projects Classic 问题）
gh api repos/matrixorigin/matrixflow/pulls/<PR_NUMBER> -X PATCH -F "body=@/tmp/pr-body.md"

# 清理
rm /tmp/pr-body.md
```

### 6. 验证更新结果
```bash
gh pr view <PR_NUMBER> --json body --jq '.body' | head -5
```

## PR 描述模板

```markdown
## 变更说明

[约100字概述整体变更背景和目的]

- 变更点 1：一句话说明
- 变更点 2：一句话说明
- 变更点 3：一句话说明

### 核心变更

**1. [模块/功能名]**
- 具体改动点 1
- 具体改动点 2

**2. [模块/功能名]**
- 具体改动点

### 调用链 / 数据流
<!-- 单模块修改：展示函数调用链；跨模块修改：展示模块间数据流 -->

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
- [ ] **Issue修复必填**（moi内核团队）：已添加能够100%复现Issue的BVT测试或单元测试

#### UT 覆盖说明
<!-- 当 PR 包含新增/修改的 UT 时必填。按函数/方法分组，用表格列出测试场景。 -->
<!-- 格式参考：
**`函数名`** — N 个 case（`test_file.go`）

| 场景 | 输入 / mock 行为 | 期望结果 |
|------|------------------|----------|
| happy path | 正常输入 | 返回预期值 |
| error path | 异常输入 / mock 返回 error | 返回 wrapped error |
| 边界条件 | 空值 / 零值 / 极端值 | 正确处理 |
| 并发安全 | 竞态条件模拟 | 无 panic / 正确降级 |
-->

#### BVT 覆盖说明
<!-- 当 PR 包含新增/修改的 BVT 或集成测试时必填。说明覆盖的端到端场景。 -->
<!-- 格式参考：
**`TestXxx`**（`test_file.go`）

覆盖场景：xxx。断言：yyy。
-->

#### 回归验证（Bug Fix PR 专项）
<!-- Issue 修复 PR 必填。说明哪个测试能在修复前 fail、修复后 pass。 -->

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
<!-- ⚠️ 此部分从原始 PR body 中原样保留，不要覆盖 -->
- GitHub Issue: （必须关联，使用 "Fixes #123" 或 "Closes #123" 格式）
- 设计文档: [链接]
- API文档: [链接]

## 截图（前端必填）

## 检查清单
- [ ] 代码已自测
- [ ] 提交信息规范
- [ ] 无调试代码
- [ ] 遵循编码规范
- [ ] 已同步上游最新代码
```

## Gotchas

1. **`gh pr edit --body` 失败**：仓库关联了 Projects Classic 时，GraphQL API 会返回 deprecation error 导致 edit 静默失败。必须用 `gh api` REST 接口替代。
2. **大 PR diff 截断**：对于大量文件变更的 PR，先用 `grep -n '^diff --git'` 定位文件边界，再按需 `sed -n` 读取关键文件的 diff，避免一次性读取全部 diff 导致上下文溢出。
3. **自动生成文件**：swagger.json、docs.go、swagger.yaml 等自动生成文件的 diff 通常很大但信息量低，应跳过或仅确认存在。
4. **Checklist 勾选**：根据实际变更内容智能勾选，不要全部勾选或全部留空。从 diff 中判断是否有文档更新、测试添加等。
5. **私有仓库**：`web_fetch` 无法访问私有仓库 PR 页面（返回 404），必须使用 `gh` CLI。
