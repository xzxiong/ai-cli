---
name: spec-worktree
description: |
  在主仓库创建 spec，创建 Git 分支和 worktree，同步 spec 到 worktree，启动新 IDE 窗口进行开发。
  一站式流程：spec → branch → worktree → sync → IDE。

  Use this skill when:
  - The user says "spec worktree" followed by a feature description
  - The user invokes `/spec-worktree <feature description>`
  - The user says "创建 spec 并开分支" or "新建 spec worktree"
  - The user says "spec branch" or "spec 开分支"
  - The user wants to create a spec and work on it in a separate worktree
---

# Spec Worktree Skill

## 目的

一站式完成：在主仓库创建 spec → 创建 Git 分支 → 创建 worktree → 同步 spec 文件到 worktree → 启动新 IDE 窗口。
适用于需要在独立分支上开发的 feature/bugfix 场景。

## 使用方法

```bash
# 基本用法
kiro chat "spec worktree 实现泛域名 TLS 证书管理"
kiro chat "spec branch 新增 ACME DNS-01 支持"

# 指定分支名
kiro chat "spec worktree --branch feat-tls-acme 实现 ACME 证书签发"

# 指定基础分支
kiro chat "spec worktree --from dev 新增用户认证模块"
```

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--branch <name>` | 自动从 spec 名推导 `feat-<spec-name>` | 分支名 |
| `--from <branch>` | `dev` | 基础分支（从哪个分支创建新分支） |
| `--no-ide` | false | 不自动打开 IDE |
| `--worktree-dir <path>` | `worktree/<branch>` | worktree 目录路径 |

## Skill 逻辑

### Step 1: 创建 Spec（在主仓库）

在当前主仓库中，按照正常 spec 流程创建 spec：

1. 询问用户选择 spec 类型（Feature / Bugfix）
2. 询问用户选择工作流（Requirements-first / Design-first）— 仅 Feature
3. 创建 `.kiro/specs/<feature-name>/` 目录
4. 生成 `requirements.md`、`design.md`、`tasks.md`（或 `bugfix.md`）
5. 等待用户确认 spec 内容

**重要**：spec 创建过程中，在 `requirements.md` 和 `tasks.md` 中注明所有代码修改在 worktree 目录下执行。

### Step 2: 确定分支名和 worktree 路径

从 spec 的 feature name 推导分支名：

```bash
# 分支名规则
# feature spec → feat-<feature-name>
# bugfix spec  → fix-<feature-name>

# 示例
# feature-name: wildcard-tls-management
# branch: feat-wildcard-tls-management
# worktree: worktree/feat-wildcard-tls-management
```

如果用户通过 `--branch` 指定了分支名，使用用户指定的值。

### Step 3: 创建 Git 分支

```bash
# 确保基础分支是最新的
git fetch origin

# 从基础分支创建新分支
git branch <branch-name> origin/<from-branch>
```

如果分支已存在，提示用户：
- 使用已有分支继续
- 指定其他分支名

### Step 4: 创建 Worktree

```bash
# 创建 worktree 目录
git worktree add worktree/<branch-name> <branch-name>
```

如果 worktree 已存在，检查是否指向正确的分支：
```bash
git worktree list
```

- 已存在且分支正确 → 跳过创建，继续同步
- 已存在但分支不同 → 提示用户处理冲突

### Step 5: 同步 Spec 到 Worktree

将主仓库的 spec 文件复制到 worktree：

```bash
# 创建目标目录
mkdir -p worktree/<branch-name>/.kiro/specs/<feature-name>/

# 复制 spec 文件
cp .kiro/specs/<feature-name>/requirements.md worktree/<branch-name>/.kiro/specs/<feature-name>/
cp .kiro/specs/<feature-name>/design.md worktree/<branch-name>/.kiro/specs/<feature-name>/
cp .kiro/specs/<feature-name>/tasks.md worktree/<branch-name>/.kiro/specs/<feature-name>/
cp .kiro/specs/<feature-name>/.config.kiro worktree/<branch-name>/.kiro/specs/<feature-name>/
```

验证同步结果：
```bash
ls -la worktree/<branch-name>/.kiro/specs/<feature-name>/
```

### Step 6: 启动 IDE

除非用户指定了 `--no-ide`，尝试在 worktree 目录打开新的 IDE 窗口：

```bash
# 尝试 kiro CLI
kiro worktree/<branch-name> 2>/dev/null

# 如果 kiro 不可用，尝试 VS Code
code worktree/<branch-name> 2>/dev/null
```

如果 CLI 不可用（远程环境等），输出手动打开指引：
```
请手动打开 IDE：
  kiro worktree/<branch-name>
  # 或
  code worktree/<branch-name>
```

### Step 7: 输出结果

```
✅ Spec 创建完成: .kiro/specs/<feature-name>/
✅ 分支已创建: <branch-name> (基于 origin/<from-branch>)
✅ Worktree 已创建: worktree/<branch-name>/
✅ Spec 已同步到 worktree
✅ IDE 已启动（或输出手动打开指引）

下一步：
  1. 在新 IDE 窗口中打开 .kiro/specs/<feature-name>/tasks.md
  2. 执行 "run all tasks" 开始实现
```

## 边界情况处理

### .gitignore 检查

确保 `worktree/` 目录在 `.gitignore` 中：
```bash
grep -q '^worktree/' .gitignore || echo 'worktree/' >> .gitignore
```

### Worktree 清理

如果用户需要清理 worktree：
```bash
git worktree remove worktree/<branch-name>
git branch -d <branch-name>  # 可选：删除分支
```

### 远程分支已存在

如果远程已有同名分支：
```bash
# 检查远程分支
git ls-remote --heads origin <branch-name>
```

- 远程存在 → `git branch <branch-name> origin/<branch-name>` 跟踪远程分支
- 远程不存在 → 从 `origin/<from-branch>` 创建新分支

## 注意事项

1. **Spec 在主仓库创建**：spec 文件首先在主仓库的 `.kiro/specs/` 下创建，然后同步到 worktree
2. **Worktree 独立工作**：worktree 中的修改不影响主仓库的工作目录
3. **分支命名约定**：feature 用 `feat-` 前缀，bugfix 用 `fix-` 前缀
4. **Tasks 路径**：tasks.md 中的文件路径应基于 `worktree/<branch>/` 目录
5. **同步是单向的**：从主仓库 → worktree，后续修改在 worktree 中进行

## Example Flow

```
User: spec worktree 实现泛域名 TLS 证书管理

Agent: [创建 spec 流程...]
       spec 类型: Feature
       工作流: Requirements-first
       feature name: wildcard-tls-management

       [生成 requirements.md, design.md, tasks.md]

       分支: feat-wildcard-tls-management (基于 origin/dev)
       Worktree: worktree/feat-wildcard-tls-management/

       ✅ Spec 创建完成
       ✅ 分支已创建: feat-wildcard-tls-management
       ✅ Worktree 已创建
       ✅ Spec 已同步
       
       请在新 IDE 窗口中执行 tasks。
```
