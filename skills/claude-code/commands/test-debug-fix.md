自动化 测试→调试→修复 迭代循环，最多 5 轮直到全部 PASS。

Input: $ARGUMENTS (测试名或测试命令)

## 确定测试命令

| 项目类型 | 命令模板 | 工作目录 |
|---------|---------|---------|
| moi-core 集成测试 | `go test . -run {Test} -v -timeout 120s -count=1` | `moi-core/tests` |
| moi-core workers | `go test ./... -run {Test} -v -timeout 60s -count=1` | `moi-core/workers/go-worker` |
| moi-core catalog | `go test ./... -run {Test} -v -timeout 60s -count=1` | `moi-core/catalog` |
| Go 服务 | `go test ./... -run {Test} -v -timeout 60s -count=1` | `{service_dir}` |
| Python | `poetry run pytest {path} -v --tb=long` | `{service_dir}/src` |

## 迭代循环

### Round N:

1. **运行测试**（输出重定向到 `/tmp/{test}_{N}.log`）

2. **分析日志**
   ```bash
   grep -E "^--- FAIL|FAIL\s+|Error Trace:|Error:|panic:" /tmp/{test}_{N}.log
   grep -B 5 -A 20 "--- FAIL" /tmp/{test}_{N}.log
   ```
   分类：断言失败 / 编译错误 / panic / 超时 / 连接错误 / 数据不一致

3. **耗时分析**
   | 类型 | 正常 | 告警 | 严重 |
   |------|------|------|------|
   | 集成测试(含Catalog启动) | 30-60s | >90s | >120s |
   | 单元测试 | <5s | >15s | >30s |
   | 单个HTTP请求 | <0.1s | >1s | >5s |
   跨轮次劣化 >50% 需回滚。

4. **修复代码**
   - 最小改动，不做无关重构
   - 修复后 `go vet` 检查
   - 不破坏其他测试

5. **重新验证** → Round N+1

### 终止条件
- 全部 PASS
- 达到 5 轮
- 基础设施问题（连接错误，提示用户检查）
- 需要架构变更

### 最终报告
```
迭代轮数 / 修改文件 / 修复的 FAIL case / 剩余未修复 / 耗时趋势
```

## 注意事项
- moi-core 多模块结构，不同测试在不同 go.mod 下运行
- 集成测试需要 MatrixOne(6001)、MinIO(9100)、OpenXML(8817)
- 必须使用 Go 1.24.x（1.25+ 导致 sonic 编译失败）
- 新 FAIL 出现时回滚上一轮修改
