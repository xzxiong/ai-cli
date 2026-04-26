---
name: new-pr
description: |
  将当前修改提交到新分支并创建 PR。自动检测仓库模式：
  - fork 模式：push 到 fork remote，PR 提到 matrixorigin 上游
  - 同仓库模式：push 到 origin，在同仓库创建 PR

  Use this skill when:
  - The user says "new pr" or "新建 pr" or "创建 pr"
  - The user invokes `/new-pr <commit message>`
  - The user says "提交新 pr" or "create pr"
  - The user wants to create a new branch from current changes and open a PR
---

# New PR Skill

## 目的
从当前修改出发：创建新分支 → commit → push → 创建 PR。自动识别 fork 模式仓库。

## 使用方法
```bash
kiro chat "new pr fix: 修复xxx问题"
kiro chat "新建 pr feat: 新增xxx功能"
kiro chat "create pr refactor: 重构xxx"
```

用户可在消息中覆盖：
- `--base main` → PR 目标分支改为 main（默认 dev）
- `--branch <name>` → 指定新分支名（默认从 commit message 自动生成）
- `--no-review` → 创建 PR 后跳过自动 review

## 仓库模式判定（通用 fork 检测）

通过扫描所有 remote URL 自动判定模式：

```bash
git remote -v
```

**判定规则**：

| 条件 | 模式 | push remote | PR repo | `--head` 格式 |
|------|------|-------------|---------|---------------|
| 存在 remote 指向 `xzxiong/<repo>` 且存在 remote 指向 `matrixorigin/<repo>` | **fork** | 指向 `xzxiong/<repo>` 的 remote | `matrixorigin/<repo>` | `xzxiong:<branch>` |
| 其他 | **同仓库** | `origin` | 从 origin URL 提取 `<owner>/<repo>` | `<branch>` |

**fork 模式检测逻辑**：
1. 遍历所有 remote，找到 URL 包含 `xzxiong/` 的 remote → 记为 `FORK_REMOTE`（名称可能是 `origin`、`xzx` 等）
2. 遍历所有 remote，找到 URL 包含 `matrixorigin/` 的 remote → 提取 `matrixorigin/<repo>` 作为 `UPSTREAM_REPO`
3. 两者都存在 → fork 模式；否则 → 同仓库模式

**已知 fork 仓库配置**：

| 仓库 | fork remote 名 | fork URL | upstream remote 名 | upstream URL |
|------|----------------|----------|---------------------|--------------|
| matrixflow | origin | `xzxiong/matrixflow` | — | `matrixorigin/matrixflow` |

**已知同仓库模式仓库**（即使存在 fork remote 也走同仓库模式）：

| 仓库 | push remote | PR repo |
|------|-------------|---------|
| matrixone-operator | origin | `matrixorigin/matrixone-operator` |

## Skill 逻辑

### 1. 检查工作区状态

```bash
git rev-parse --is-inside-work-tree
CURRENT_BRANCH=$(git branch --show-current)
```

### 2. 检测仓库模式

```bash
FORK_REMOTE=""
UPSTREAM_REPO=""

for remote in $(git remote); do
  url=$(git remote get-url "$remote")
  if [[ "$url" == *"xzxiong/"* ]]; then
    FORK_REMOTE="$remote"
  fi
  if [[ "$url" == *"matrixorigin/"* ]]; then
    UPSTREAM_REPO=$(echo "$url" | grep -oP 'matrixorigin/[^/.]+')
  fi
done

if [[ -n "$FORK_REMOTE" && -n "$UPSTREAM_REPO" ]]; then
  # 检查是否在同仓库模式白名单中（如 matrixone-operator）
  REPO_NAME=$(echo "$UPSTREAM_REPO" | sed 's|matrixorigin/||')
  SAME_REPO_LIST="matrixone-operator"
  if echo "$SAME_REPO_LIST" | grep -qw "$REPO_NAME"; then
    MODE="same-repo"
    PUSH_REMOTE="origin"
    PR_REPO="$UPSTREAM_REPO"
  else
    MODE="fork"
    PUSH_REMOTE="$FORK_REMOTE"
    PR_REPO="$UPSTREAM_REPO"
  fi
else
  MODE="same-repo"
  PUSH_REMOTE="origin"
  PR_REPO=$(git remote get-url origin | grep -oP '[^/:]+/[^/.]+$')
fi
```

### 3. 检查变更

```bash
git status --porcelain
```

- 有变更 → 继续
- 无变更 → 提示用户，终止

### 4. 确定分支名

如果用户通过 `--branch` 指定了分支名，使用它。否则从 commit message 自动生成：

- `fix: 修复删除线检测` → `fix/修复删除线检测`
- `feat: add export API` → `feat/add-export-API`

规则：取 `<type>/<summary>`，空格替换为 `-`，截断到 50 字符。

### 5. 创建新分支并 Commit

如果当前在主分支（`main`/`master`/`dev`），从当前 HEAD 创建新分支：

```bash
git checkout -b <new-branch>
git add -A
git commit -m "<message>"
```

如果当前已在 feature 分支，直接 commit（不创建新分支）：

```bash
git add -A
git commit -m "<message>"
```

### 6. Push

```bash
# 推送到检测到的 remote（fork 模式下可能是 origin 或 xzx 等）
git push -u $PUSH_REMOTE <branch>
```

### 7. 创建 PR

先检查是否已有 PR：

**fork 模式**：
```bash
gh pr list --repo $PR_REPO --head xzxiong:<branch> --state open --json number,url
```

**同仓库模式**：
```bash
gh pr list --repo $PR_REPO --head <branch> --state open --json number,url
```

已有 PR → 输出 URL，不重复创建。

无 PR → 创建：

**fork 模式**：
```bash
gh pr create \
  --repo $PR_REPO \
  --base dev \
  --head xzxiong:<branch> \
  --title "<commit message>" \
  --body ""
```

**同仓库模式**：
```bash
gh pr create \
  --repo $PR_REPO \
  --base dev \
  --head <branch> \
  --title "<commit message>" \
  --body ""
```

### 8. 自动生成 PR 描述 + Code Review

PR 创建成功后，主代理自己依次执行：

**Step 8a: 更新 PR 描述**
读取 `update-pr-desc` skill 并执行其逻辑，通过 `gh api` 更新 PR body。

**Step 8b: Code Review**（除非 `--no-review`）
读取 `review-pr` skill 并执行其逻辑，生成审查报告并发布为 PR comment。

⚠️ 步骤 8a 和 8b 必须由主代理自己执行，不要委托给 subagent。

### 9. 输出结果

```
✅ Branch: <branch>
✅ Committed: <short sha> <message>
✅ Pushed: $PUSH_REMOTE (<fork-or-repo>) ← <branch>
✅ PR: https://github.com/$PR_REPO/pull/<number>
✅ PR Description: updated
✅ Code Review: posted
```

## Gotchas

1. **主分支保护**：`main`/`master`/`dev` 禁止直接 push，必须创建新分支。
2. **repo 名提取**：从 remote URL 中提取，支持 SSH（`git@github.com:owner/repo.git`）和 HTTPS（`https://github.com/owner/repo.git`）格式。
3. **head 格式**：fork 模式下 `--head` 必须带 `xzxiong:` 前缀。
4. **已有 PR**：当前分支已有 open PR 时只 push 不重复创建。
5. **fork remote 名不固定**：不同仓库的 fork remote 名可能不同（`origin`、`xzx` 等），通过 URL 内容而非 remote 名判定。
