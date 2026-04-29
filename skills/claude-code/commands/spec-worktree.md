在主仓库创建 spec，创建 Git 分支和 worktree，同步 spec 到 worktree，启动新 IDE 窗口。

Input: $ARGUMENTS (feature description, 可选: --branch <name>, --from <branch>, --no-ide, --worktree-dir <path>)

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--branch <name>` | 自动推导 `feat-<spec-name>` | 分支名 |
| `--from <branch>` | `dev` | 基础分支 |
| `--no-ide` | false | 不自动打开 IDE |
| `--worktree-dir <path>` | `worktree/<branch>` | worktree 目录路径 |

## 流程

### 1. 创建 Spec（在主仓库）
按正常 spec 流程创建 `.kiro/specs/<feature-name>/`，生成 `requirements.md`、`design.md`、`tasks.md`。
在文档中注明所有代码修改在 worktree 目录下执行。

### 2. 确定分支名和 worktree 路径
```
feature spec → feat-<feature-name>
bugfix spec  → fix-<feature-name>
```
用户 `--branch` 指定则使用指定值。

### 3. 创建 Git 分支
```bash
git fetch origin
git branch <branch-name> origin/<from-branch>
```
分支已存在则提示用户：使用已有分支或指定其他名称。

### 4. 创建 Worktree
```bash
git worktree add worktree/<branch-name> <branch-name>
```
已存在且分支正确 → 跳过；分支不同 → 提示用户。

### 5. 同步 Spec 到 Worktree
```bash
mkdir -p worktree/<branch-name>/.kiro/specs/<feature-name>/
cp .kiro/specs/<feature-name>/{requirements.md,design.md,tasks.md,.config.kiro} \
   worktree/<branch-name>/.kiro/specs/<feature-name>/
```

### 6. 启动 IDE（除非 --no-ide）
```bash
code worktree/<branch-name> 2>/dev/null
```
不可用时输出手动打开指引。

### 7. 输出
```
✅ Spec 创建完成: .kiro/specs/<feature-name>/
✅ 分支已创建: <branch-name> (基于 origin/<from-branch>)
✅ Worktree 已创建: worktree/<branch-name>/
✅ Spec 已同步到 worktree
下一步: 在新窗口中打开 tasks.md，执行 "run all tasks"
```

## 边界情况

- **`.gitignore` 检查**: 确保 `worktree/` 在 `.gitignore` 中
- **远程分支已存在**: `git ls-remote --heads origin <branch>` 检查，存在则跟踪远程
- **Worktree 清理**: `git worktree remove worktree/<branch>` + `git branch -d <branch>`

## 注意事项

1. Spec 在主仓库创建，然后同步到 worktree
2. Worktree 中的修改不影响主仓库工作目录
3. 分支命名: feature → `feat-`, bugfix → `fix-`
4. 同步是单向的: 主仓库 → worktree
