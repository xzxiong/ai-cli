---
name: turbo-issue-fix
description: |
  端到端修复 Turbo GitHub Issue：分析→设计→UT→Fix→回归→同步 Issue Comment。

  Use this skill when:
  - The user says "fix issue" followed by a turbo issue URL or number
  - The user says "修 issue" or "修复 issue" with a turbo issue URL or number
  - The user provides a turbo issue URL with a comment link and asks to fix it

  **Agent**: The main agent reads the issue, analyzes code, designs the fix, writes tests, implements, verifies, and posts results back to the issue.
---

# Turbo Issue Fix Skill

## 目的
端到端修复 Turbo 项目的 GitHub Issue，遵循 TDD 流程，并将分析设计同步回 Issue Comment。

## 使用方法
```bash
kiro chat "fix issue https://github.com/matrixorigin/turbo/issues/<NUMBER>"
kiro chat "fix issue https://github.com/matrixorigin/turbo/issues/<NUMBER>#issuecomment-<ID>"
```

## Skill 逻辑

### 1. 获取 Issue 信息
```bash
gh issue view <NUMBER> --repo matrixorigin/turbo --json title,body,labels,state,comments
# 如果有 comment 链接，获取具体 comment
gh api repos/matrixorigin/turbo/issues/comments/<COMMENT_ID> --jq '.body'
```

从 Issue body + comments 中提取：
- 问题现象和复现步骤
- 涉及的模块/文件
- 期望行为

### 2. 分析现有代码

根据 Issue 描述定位相关代码：
- 使用 code 工具搜索相关符号和文件
- 读取涉及的源文件，理解数据流和逻辑
- 确认根因（后端 API、前端展示、数据模型等）

关键目录：
- `pkg/model/` — 数据模型
- `pkg/api/` — HTTP 处理器
- `pkg/engine/` — 事件总线 + 编排器
- `pkg/governance/` — 状态机 + 积分
- `pkg/agent/` — AI Agent
- `pkg/store/` — 存储层
- `apps/web/` — 前端 Web 控制台

### 3. 设计方案并同步到 Issue

输出结构化设计方案，包含：
- 根因分析
- 变更文件和具体修改点
- 影响范围评估

同步到 Issue Comment：
```bash
gh issue comment <NUMBER> --repo matrixorigin/turbo --body '<设计方案 markdown>'
```

### 4. 编写测试（TDD）

先写测试，后写实现：

**Go 后端测试**：
- 单元测试放在对应包的 `_test.go` 文件中
- 通过 `make ut` 运行（使用 `-short` flag）
- 集成测试函数名以 `TestIntegration` 开头

**前端 E2E 测试**：
- 测试文件在 `apps/web/e2e/workspace.spec.ts`
- 使用 Playwright + mock API 模式
- 通过 `make web-e2e` 运行

### 5. 实现 Fix

按设计方案实施最小变更：
- 仅修改与根因直接相关的代码
- 保持现有代码风格和约定
- 前端变更需确保 `next build` 通过
- 后端变更需确保 `make ut` 通过

### 6. 回归验证

```bash
# Go 后端
make ut

# 前端编译
cd apps/web && npx next build

# E2E 测试（需要 Chrome 环境）
make web-e2e
```

### 7. 总结变更

列出所有变更文件和修改点，确认：
- TypeScript 编译通过
- Go 单元测试全部通过
- E2E 测试代码已编写（可通过 `make web-e2e` 运行）

## 项目约定

- **不要直接运行 `go test`**，使用 `make ut` 或 `make ci`
- ID 生成使用 `pkg/xid.New()`
- 可空字段使用 `*string`、`*float64`、`*time.Time`
- 幂等性：关键写路径携带 `idempotency_key`
- 分页：`(limit, offset)` 模式
- 类型安全：不用 `map` 做跨层参数，用显式 struct

## Gotchas

1. **前端 E2E 测试环境**：`make web-e2e` 需要 Chrome 浏览器，CI 环境可能不可用。确保 `next build` 通过作为基本验证。
2. **静态导出**：Web 使用 `output: "export"`，`next start` 不可用，E2E 测试通过 `make web-e2e` 脚本处理。
3. **API mock 端口**：E2E mock 拦截 `apiBase`（默认 `http://127.0.0.1:3000`）的请求，`normalizeServiceURL` 会将不同端口的 loopback 地址归一化到浏览器 origin。
4. **Issue 模板**：turbo 仓库有结构化 Issue 模板（`.github/ISSUE_TEMPLATE/issue.yml`），创建 Issue 时需按模板填写所有必填字段。
