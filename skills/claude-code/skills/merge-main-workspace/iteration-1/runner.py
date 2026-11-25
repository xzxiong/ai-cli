---
name: merge-main
description: |
  合并目标分支到当前分支，全面解决 merge conflict。
  自动检测默认分支：MatrixFlow/moi- 系列仓库默认合并 dev，其他仓库默认合并 main。
  不仅解决文本冲突，还会追踪所有受影响的调用链、单元测试、E2E 测试、
  外围工具适配（CI/CD、Dockerfile、scripts 等），确保合并后代码可编译、可通过测试。

  Use this skill when:
  - The user says "merge main", "合并 main", "merge latest main"
  - The user says "merge dev", "合并 dev"
  - The user says "resolve conflicts", "解决冲突"
  - The user asks to update their branch with upstream changes

triggers:
  - "merge main"
  - "merge latest main"
  - "merge dev"
  - "合并 main"
  - "合并 dev"
  - "resolve conflicts"
  - "解决冲突"
  - "update from main"
  - "update from dev"
  - "rebase main"
  - "rebase dev"
---

# Merge Main — 全面合并与冲突解决

合并目标分支到当前分支，解决所有冲突并确保编译、测试通过。

## Input

`<branch>` (可选，自动检测默认分支)，可选 flag：`--rebase`（使用 rebase 而非 merge）

## 默认分支检测

根据仓库自动选择目标分支：

| 仓库 / remote 特征 | 默认目标分支 |
|---|---|
| `matrixflow` / `moi-` 系列仓库 (remote URL 含 `matrixflow` 或 `moi-`) | `dev` |
| 其他仓库 | `main` |

检测逻辑（Step 1 中执行）：
```bash
# 通过 remote URL 判断是否为 MatrixFlow 系列仓库
git remote -v | grep -qiE '(matrixflow|/moi-)' && echo "dev" || echo "main"
```

用户显式指定 `<branch>` 时，跳过自动检测。

## 核心原则

**冲突解决不仅仅是文本合并。** 每个冲突文件都可能影响：
1. **调用方** — 谁在调用这个函数/接口？签名变了调用方要跟着变
2. **单元测试** — 测试中的 mock、helper、断言是否还匹配
3. **E2E 测试** — 集成测试中的 store/handler 调用是否适配新签名
4. **外围工具** — CI workflow、Dockerfile、scripts、配置文件是否需要同步更新

## 执行流程

### Step 1. 预检查 & 分支检测

```bash
git status --porcelain          # 确保工作区干净
git branch --show-current       # 记录当前分支
git stash list                  # 如有未提交修改，提示用户先 stash 或 commit

# 自动检测目标分支（如用户未指定）
TARGET_BRANCH=$(git remote -v | grep -qiE '(matrixflow|/moi-)' && echo "dev" || echo "main")
```

如果工作区不干净，提示用户处理后再执行。

### Step 2. Fetch & Merge

```bash
# 确定上游 remote（fork 模式 vs 同仓库模式）
git remote -v

# Fetch 最新
git fetch <upstream-remote> <target-branch>

# 执行合并
git merge <upstream-remote>/<target-branch>
# 或 --rebase 模式: git rebase <upstream-remote>/<target-branch>
```

如果无冲突，跳到 Step 6。

### Step 3. 分析冲突文件

```bash
git diff --name-only --diff-filter=U   # 列出所有冲突文件
```

对每个冲突文件进行分类：
| 类别 | 文件模式 | 解决策略 |
|------|---------|---------|
| 接口/类型定义 | `model/`, `store/interface`, `types.go` | 高优先级，先解决 |
| 实现层 | `store/`, `service/`, `handlers/` | 中优先级，依赖接口层 |
| 路由/配置 | `router.go`, `config/`, `*.toml` | 合并双方意图 |
| 测试 | `*_test.go` | 最后解决，依赖实现层 |
| CI/工具 | `.github/`, `Dockerfile`, `scripts/` | 独立解决 |

### Step 4. 解决冲突（按优先级）

对每个冲突文件：

#### 4.1 读取冲突内容
```bash
# 查看冲突标记
grep -n "<<<<<<< HEAD\|=======\|>>>>>>>" <file>
```

#### 4.2 理解双方意图
- **HEAD（当前分支）**：我们添加/修改了什么？为什么？
- **theirs（目标分支）**：上游修改了什么？为什么？
- 参考对应的 commit message 理解上下文

#### 4.3 解决冲突
根据分析合并双方修改。两边的功能性代码都应保留，除非明确冲突。

#### 4.4 追踪影响范围（关键步骤）

对于**接口/签名变更类冲突**，必须额外检查：

```bash
# 查找所有调用方
grep -rn "<changed_function_name>" --include="*.go" .

# 查找测试中的使用
grep -rn "<changed_function_name>" --include="*_test.go" .

# 查找 mock/helper 中的使用
grep -rn "<changed_type_or_interface>" --include="*.go" .
```

逐一确认调用方是否需要适配。

### Step 5. 修复非冲突文件中的连锁影响

合并后即使某些文件没有冲突标记，也可能因为依赖的接口/类型变化而需要修改。

```bash
# 编译检查 — 这是发现连锁影响的最有效手段
go build ./...

# 如果编译失败，分析错误
# 常见模式：
# - "assignment mismatch: N variables but X returns M values" → 函数签名变了
# - "undefined: SomeType" → 类型被移除或重命名
# - "cannot use X as type Y" → 接口变了
# - "too many arguments" / "not enough arguments" → 参数变了
```

对每个编译错误：
1. 定位错误源头（是哪个接口/函数变了）
2. 查看上游是如何使用新签名的（参考 main 分支的 test 或实现）
3. 适配当前分支的代码

### Step 6. 验证

```bash
# 1. 编译通过
go build ./...

# 2. vet 通过
go vet ./...

# 3. 单元测试（快速验证）
go test ./pkg/... -count=1 -short 2>&1 | tail -20

# 4. 如果有 E2E 测试相关修改
go test ./tests/e2e/... -count=1 -short 2>&1 | tail -20
```

### Step 7. 完成合并

```bash
# 如果是 merge 模式
git add -A    # 注意排除不应提交的文件（.claude/, .mcp.json 等）
git commit    # 使用默认的 merge commit message

# 如果是 rebase 模式
git rebase --continue
```

### Step 8. 报告

输出合并报告：
```
✅ Merged: <upstream>/<branch> into <current-branch>
📁 Conflicts resolved: N files
🔧 Additional adaptations: M files (non-conflict changes needed)
🏗️  Build: ✅ pass
🧪 Tests: ✅ pass (or ⚠️ with details)
```

## 冲突解决 Checklist

Read `~/.claude/skills/merge-main/references/conflict-checklist.md` for the detailed checklist.

## Gotchas

1. **不要用 `git add -A` 盲目添加所有文件** — 先 `git status` 确认不会意外提交 `.claude/`、`.mcp.json`、IDE 配置等
2. **接口变更是连锁反应的根源** — 一个 Store 方法签名变了，所有 mock、test helper、e2e 调用都要查
3. **Go 的编译器是最好的检查工具** — 解决完冲突后立即 `go build ./...`
4. **commit message 中保留冲突解决的上下文** — 如果做了非 trivial 的合并决策，在 commit message 中说明
5. **注意 go.mod/go.sum 冲突** — 通常取 theirs 然后 `go mod tidy`
6. **generated 文件（swagger.json、docs.go）** — 取 theirs 版本或重新生成，不要手动合并
7. **fork 模式下注意 remote 名称** — upstream 可能叫 `upstream`、`origin`、或其他名字
