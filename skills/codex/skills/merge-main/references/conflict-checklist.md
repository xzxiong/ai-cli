# Conflict Resolution Checklist

解决每个冲突文件时，逐项确认以下检查点。

## 一、接口/类型变更（最高优先级）

当冲突涉及接口定义、struct 字段、函数签名时：

- [ ] **调用方适配**：`grep -rn "<func_name>" --include="*.go"` 找到所有调用方
- [ ] **接口实现**：如果接口方法变了，所有 implementor 是否都更新了？
- [ ] **Mock 更新**：测试中的 mock struct 是否实现了新接口？
- [ ] **类型断言**：代码中是否有 `x.(InterfaceName)` 需要更新？

## 二、Store/数据层变更

当冲突涉及 store 方法时：

- [ ] **返回值变化**：`Create*` 从 `T` 变为 `(T, error)` → 所有调用方都要处理 error
- [ ] **参数变化**：新增/移除参数 → 所有调用方都要适配
- [ ] **test helper**：`mustCreateXxx` 等 helper 是否需要更新签名？
- [ ] **storetest 包**：测试工具包中的 helper 是否需要更新？
- [ ] **E2E 测试**：`tests/e2e/` 中直接调用 store 的代码是否适配？

## 三、Handler/路由变更

当冲突涉及 HTTP handler 或路由注册时：

- [ ] **构造函数参数**：`New()` / `NewWithXxx()` 参数是否变了？
- [ ] **路由注册**：新路由是否正确注册？旧路由是否保留？
- [ ] **中间件**：中间件链是否完整（auth、drain、cors、logging）？
- [ ] **Handler 接口**：如果 Handler struct 加了字段，所有构造处是否传入？

## 四、单元测试适配

- [ ] **Test helper 签名**：helper 函数参数是否匹配新的被测函数？
- [ ] **Mock struct**：mock 是否实现了完整的接口（编译会报错）？
- [ ] **断言更新**：期望值是否因上游变更而需要调整？
- [ ] **Test fixture/catalog**：测试数据安装函数是否适配新 API？

## 五、E2E 测试适配

- [ ] **Harness 函数**：`startMemoryTaaS` 等 harness 是否使用新的 store/config？
- [ ] **直接 store 调用**：E2E 测试中直接调用 `st.CreateXxx()` 的地方是否适配？
- [ ] **Token/Auth helper**：认证相关 helper 是否仍然兼容？
- [ ] **HTTP 请求路径**：路由变更是否导致 E2E 请求路径失效？

## 六、外围工具适配

- [ ] **CI Workflow** (`.github/workflows/`)：
  - 新的 secret/env var 是否已配置？
  - 步骤顺序是否因新依赖而需要调整？
  - checkout/build 命令是否需要更新？
- [ ] **Dockerfile**：
  - 新的依赖/文件是否需要 COPY？
  - 构建阶段是否需要调整？
- [ ] **docker-compose.yaml**：
  - 新的 service/volume/env 是否需要添加？
- [ ] **Scripts** (`scripts/`, `deploy/`)：
  - 脚本中引用的路径/命令是否仍然有效？
- [ ] **配置文件** (`etc/`, `*.toml`, `*.yaml`)：
  - 新配置项是否需要添加到各环境的配置中？

## 七、Go Module 冲突

- [ ] **go.mod**：取 theirs 版本，然后 `go mod tidy`
- [ ] **go.sum**：删除后 `go mod tidy` 重新生成
- [ ] **vendor/**（如果有）：`go mod vendor` 重新生成

## 八、生成文件

- [ ] **swagger/openapi**：取 theirs 或重新 `swag init`
- [ ] **protobuf**：取 theirs 或重新 `protoc`
- [ ] **wire/mockgen**：取 theirs 或重新 `go generate`

## 九、最终验证

```bash
# 必须全部通过才能 commit
go build ./...           # 编译
go vet ./...             # 静态分析
go test ./... -short     # 快速测试（视项目大小决定范围）
```

## 十、Commit 规范

合并 commit 应说明：
- 合并了什么（哪个分支/PR）
- 做了哪些非 trivial 的合并决策
- 哪些文件做了超出冲突标记范围的适配

示例：
```
merge main: adapt to store error-return refactor (PR #39)

- Resolved conflicts in router.go, handlers.go
- Adapted graceful_shutdown_test.go to new (T, error) signatures
- Updated mustCreate* helpers to use new store API
```
