# Layout examples — feature-iface-flow

示意落盘，按模块现有风格裁剪；**一致性优先于本文件字面**。

## Go（包内）

```text
pkg/billing/
  suspend.go              # 接口 + 契约类型/错误（或 suspend_iface.go）
  suspend_impl.go         # 正式实现
  suspend_mock_test.go    # 测试用 Mock（_test 包内）
  suspend_contract_test.go
  orchestrator.go         # 只依赖接口
  orchestrator_test.go    # 注入 Mock
```

契约测试共用入口示意：

```go
type SuspendDep interface {
    Claim(ctx context.Context, id string) error
    Release(ctx context.Context, id string) error
}

func runSuspendContract(t *testing.T, newDep func(t *testing.T) SuspendDep) {
    t.Helper()
    t.Run("M0_claim_release", func(t *testing.T) { /* … */ })
    t.Run("B1_claim_conflict", func(t *testing.T) { /* … */ })
}

func TestSuspendContract_Mock(t *testing.T) {
    runSuspendContract(t, func(t *testing.T) SuspendDep { return newMockSuspend(t) })
}

func TestSuspendContract_Impl(t *testing.T) {
    // 可选：需要 fixture 时跳过或建最小资源
    runSuspendContract(t, func(t *testing.T) SuspendDep { return newImpl(t) })
}
```

测试意义注释：

```go
// 意义: M0 — Claim 成功后 Release 必须可重复调用且第二次无错误（幂等契约）
func TestMock_ReleaseIdempotent(t *testing.T) { /* … */ }
```

## Go（跨包可复用 Mock）

```text
pkg/billing/
  suspend.go
  suspend_impl.go
pkg/billing/billingtest/
  suspend_mock.go         // 供外部包 e2e/编排测
```

## TypeScript

```text
src/suspend/types.ts          # 接口与错误联合类型
src/suspend/impl.ts
src/suspend/mock.ts
src/suspend/contract.test.ts
src/suspend/orchestrator.ts
src/suspend/orchestrator.test.ts
```

## Python

```text
suspend/protocol.py           # Protocol / ABC
suspend/impl.py
suspend/mock.py
tests/test_suspend_contract.py
tests/test_orchestrator.py
```

## e2e 用 Mock 拼装

```text
e2e/
  harness.go                  # 组装 Mock 依赖 + 进程内服务
  mvp_m0_test.go              # 白话 M0 的自动化
  boundary_b1_test.go
```

真实依赖套件单独目录或 build tag，避免默认 `go test ./...` 被环境拖垮。
