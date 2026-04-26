---
name: add-submodule
description: |
  在当前仓库的 third/ 目录下通过 git submodule add 添加外部仓库，并自动更新 AGENTS.md 追加 submodule 说明。

  Use this skill when:
  - The user says "add submodule" followed by a repo URL
  - The user invokes `/add-submodule <repo-url>`
  - The user says "添加 submodule" or "添加子模块"
  - The user wants to add a git submodule under third/
---

# Add Submodule Skill

## 目的

一站式完成：git submodule add → 更新 AGENTS.md，减少手动操作。

## 使用方法

```bash
kiro chat "add submodule git@github.com:matrixorigin/mocloud-services.git"
kiro chat "添加子模块 git@github.com:matrixorigin/matrixone.git"

# 指定子目录名（默认从 repo URL 推导）
kiro chat "add submodule git@github.com:matrixorigin/mocloud-services.git --name mocloud"

# 指定分支
kiro chat "add submodule git@github.com:matrixorigin/mocloud-services.git --branch main"
```

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `<repo-url>` | 必填 | 要添加的 git 仓库 URL（SSH 或 HTTPS） |
| `--name <dir>` | 从 URL 推导（去掉 `.git` 后缀） | submodule 在 `third/` 下的目录名 |
| `--branch <branch>` | 无（使用远程默认分支） | 跟踪的分支 |

## Skill 逻辑

### Step 1: 确认在 git 仓库中

```bash
git rev-parse --is-inside-work-tree
```

如果不在 git 仓库中，报错退出。

### Step 2: 从 URL 推导目录名

从 repo URL 中提取仓库名作为 `third/` 下的目录名：

```
git@github.com:matrixorigin/mocloud-services.git → mocloud-services
https://github.com/matrixorigin/matrixone.git    → matrixone
```

如果用户通过 `--name` 指定了目录名，使用用户指定的值。

### Step 3: 检查是否已存在

```bash
# 检查 submodule 是否已注册
git submodule status third/<dir> 2>/dev/null
```

- 已存在 → 提示用户，跳过添加
- 不存在 → 继续

### Step 4: 添加 submodule

```bash
mkdir -p third

# 无 --branch
git submodule add <repo-url> third/<dir>

# 有 --branch
git submodule add -b <branch> <repo-url> third/<dir>
```

验证添加成功：
```bash
git submodule status third/<dir>
```

### Step 5: 更新 AGENTS.md

读取当前仓库根目录的 `AGENTS.md`。如果文件不存在，创建一个基础模板。

在文件末尾（或 `## Submodules` 段落下，如果已存在）追加：

```markdown
## Submodules

### third/<dir>

Git submodule，源仓库：`<repo-url>`

```bash
# 初始化（clone 后首次）
git submodule update --init third/<dir>

# 更新到远程最新
git submodule update --remote third/<dir>

# 全量初始化所有 submodule
git submodule update --init --recursive
```
```

如果 `AGENTS.md` 中已有 `## Submodules` 段落，在该段落末尾追加新的 `### third/<dir>` 小节，不重复添加 `## Submodules` 标题。

如果 `third/<dir>` 的说明已存在，跳过更新并提示用户。

### Step 6: 输出结果

```
✅ Submodule 已添加: third/<dir> ← <repo-url>
✅ AGENTS.md 已更新: 添加了 third/<dir> 的 submodule 说明

下一步：
  git commit -m "chore: add submodule third/<dir>"
```

## 边界情况

1. **third/ 目录不存在**：自动创建。
2. **AGENTS.md 不存在**：创建基础文件并写入 submodule 段落。
3. **submodule 已存在**：提示用户，不重复添加。
4. **网络不通**：`git submodule add` 失败时输出错误信息，不更新 AGENTS.md。
5. **.gitmodules 冲突**：提示用户手动解决。
