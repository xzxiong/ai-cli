端到端修复 Turbo GitHub Issue：分析→设计→UT→Fix→回归→同步 Issue Comment。

Input: $ARGUMENTS (turbo issue URL 或 number, 可含 comment 链接)

## 流程

### 1. 获取 Issue 信息
```bash
gh issue view <NUMBER> --repo matrixorigin/turbo --json title,body,labels,state,comments
gh api repos/matrixorigin/turbo/issues/comments/<COMMENT_ID> --jq '.body'  # 如有 comment 链接
```
提取：问题现象、复现步骤、涉及模块、期望行为。

### 2. 分析现有代码
根据 Issue 描述定位相关代码，搜索相关符号和文件，理解数据流和逻辑。

关键目录：
- `pkg/model/` — 数据模型
- `pkg/api/` — HTTP 处理器
- `pkg/engine/` — 事件总线 + 编排器
- `pkg/governance/` — 状态机 + 积分
- `pkg/agent/` — AI Agent
- `pkg/store/` — 存储层
- `apps/web/` — 前端 Web 控制台

### 3. 设计方案并同步到 Issue
输出结构化方案（根因分析、变更文件、影响范围），同步到 Issue Comment：
```bash
gh issue comment <NUMBER> --repo matrixorigin/turbo --body '<设计方案>'
```

### 4. 编写测试（TDD）
**Go 后端**: 单元测试放对应包 `_test.go`，通过 `make ut` 运行（`-short` flag）。集成测试函数名以 `TestIntegration` 开头。
**前端 E2E**: `apps/web/e2e/workspace.spec.ts`，Playwright + mock API，通过 `make web-e2e` 运行。

### 5. 实现 Fix
最小变更，保持现有风格。前端需 `next build` 通过，后端需 `make ut` 通过。

### 6. 回归验证
```bash
make ut                          # Go 后端
cd apps/web && npx next build    # 前端编译
make web-e2e                     # E2E 测试
```

### 7. 总结变更
列出所有变更文件和修改点。

## 项目约定

- 不要直接运行 `go test`，使用 `make ut` 或 `make ci`
- ID 生成: `pkg/xid.New()`
- 可空字段: `*string`、`*float64`、`*time.Time`
- 幂等性: 关键写路径携带 `idempotency_key`
- 分页: `(limit, offset)` 模式
- 类型安全: 不用 `map` 做跨层参数，用显式 struct

## Gotchas

1. `make web-e2e` 需要 Chrome，CI 环境可能不可用。`next build` 通过作为基本验证。
2. Web 使用 `output: "export"`，`next start` 不可用。
3. E2E mock 拦截 `apiBase`（默认 `http://127.0.0.1:3000`），`normalizeServiceURL` 会归一化到浏览器 origin。
4. turbo 仓库有结构化 Issue 模板（`.github/ISSUE_TEMPLATE/issue.yml`）。
