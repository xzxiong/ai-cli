---
name: merge-main
description: |
  合并目标分支到当前分支，全面解决 merge conflict。
  自动检测默认分支：MatrixFlow/moi- 系列仓库默认合并 dev，其他仓库默认合并 main。
  不仅解决文本冲突，还会追踪所有受影响的调用链、单元测试、E2E 测试、
  外围工具适配（CI/CD、Dockerfile、scripts 等），确保合并后代码可编译、可通过测试。
  支持 `--gates`：完成原合并后，按 .github/workflows 中 gates-ci 的选择与命令执行本地回归，
  修复测试问题并复跑；未加此参数时保持原有行为。

  Use this skill when:
  - The user says "merge main", "合并 main", "merge latest main"
  - The user says "merge dev", "合并 dev"
  - The user says "resolve conflicts", "解决冲突"
  - The user asks to update their branch with upstream changes

---

# Merge Main — 全面合并与冲突解决

合并目标分支到当前分支，解决所有冲突并确保编译、测试通过。

## Input

`<branch>`（可选，自动检测默认分支），可选 flags：

- `--rebase`：使用 rebase 而非 merge。
- `--gates`：完成原有合并和 Step 7 后，运行 gates-ci 本地回归并修复测试问题。默认不启用。基础验证与 gates 选择重叠时保留最终结果，无需机械重复同一命令。

`/merge-main [branch] [--rebase] [--gates]` 中的 flags 可组合、顺序不限；`--gates` 不接受值。不要把 `--gates` 当成目标分支。

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

如果指定了 `--gates`，后续 gate 修复不属于本步；按下面的可选阶段处理，不自动追加提交。

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

## `--gates`：合并后回归（可选）

只有用户显式指定 `--gates` 时，才在 Step 7 后、最终报告前执行本阶段。原流程的冲突解决、连锁适配、基础验证和 merge/rebase 完成方式不变；合并尚未完成或有未解决冲突时，先解决，不能靠 gates 绕过。

执行前完整读取 `~/.claude/skills/merge-main/references/gates-regression.md`，按其中的选择、执行、修复和报告规则处理。核心要求：

1. 读取合并后的 `.github/workflows/gates-ci.{yml,yaml}` 及 caller、触发条件和仓库 CI 文档，选择实际命中的检查；不要固定运行一组通用 Go 测试冒充 gates-ci。
2. 优先使用仓库现有本地调度器或 Make 入口。没有 gates-ci 时明确 `SKIPPED`，而不是静默省略。
3. 逐项记录 `PASS` / `FAIL` / `FIXED` / `NOT RUN` / `BLOCKED`。只有实际执行并成功退出的检查才是 `PASS`；本地无法复现的 CI-only 步骤不等于通过。
4. 失败先归因，再修复实现、测试或外围适配；定向复跑通过后，重跑所选 gates 集合。禁止通过跳过、放宽断言、白名单、缩减范围或调阈值修绿。
5. gates 修复保持未提交，除非用户另行授权提交；不要擅自 amend 已完成的 merge 或改写 rebase 历史。
6. 未指定 `--gates` 时，不读取上述 reference，不扫描 workflow，也不运行额外的 gates 回归。

## Gotchas

1. **不要用 `git add -A` 盲目添加所有文件** — 先 `git status` 确认不会意外提交 `.claude/`、`.mcp.json`、IDE 配置等
2. **接口变更是连锁反应的根源** — 一个 Store 方法签名变了，所有 mock、test helper、e2e 调用都要查
3. **Go 的编译器是最好的检查工具** — 解决完冲突后立即 `go build ./...`
4. **commit message 中保留冲突解决的上下文** — 如果做了非 trivial 的合并决策，在 commit message 中说明
5. **注意 go.mod/go.sum 冲突** — 通常取 theirs 然后 `go mod tidy`
6. **generated 文件（swagger.json、docs.go）** — 取 theirs 版本或重新生成，不要手动合并
7. **fork 模式下注意 remote 名称** — upstream 可能叫 `upstream`、`origin`、或其他名字
