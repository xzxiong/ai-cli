---
name: git-push-pr
description: |
  提交代码、推送分支、创建 PR 的一站式流程。自动检测仓库模式：
  - fork 模式：push 到 fork remote，PR 提到 matrixorigin 上游
  - 同仓库模式：push 到 origin，在同仓库创建 PR

  Use this skill when:
  - The user says "push" or "提交" followed by commit message
  - The user invokes `/git-push-pr <commit message>`
  - The user says "push pr" or "提交并创建pr"
  - The user says "commit and push" or "push and create pr"
---

# Git Push & PR Skill

## 目的
一站式完成：commit → push → create PR，减少重复操作。

## 使用方法
```bash
kiro chat "push 修复了xxx问题"
kiro chat "push pr feat: 新增xxx功能"
kiro chat "提交 fix: 修复删除线检测"
```

用户可在消息中覆盖：
- `--base main` → PR 目标分支改为 main（默认 dev）
- `--repo other-org/repo` → PR 目标仓库
- `--remote upstream` → push 到其他 remote
- `--no-pr` → 只 push 不创建 PR
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
git branch --show-current
git remote -v
```

如果当前分支是 `dev` 或 `main`，**拒绝操作**并提示用户先创建 feature 分支。

### 2. 检测仓库模式

```bash
# 扫描所有 remote
FORK_REMOTE=""
UPSTREAM_REPO=""

for remote in $(git remote); do
  url=$(git remote get-url "$remote")
  if [[ "$url" == *"xzxiong/"* ]]; then
    FORK_REMOTE="$remote"
  fi
  if [[ "$url" == *"matrixorigin/"* ]]; then
    # 提取 matrixorigin/<repo>
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

- 有未暂存的变更 → `git add -A` 然后 commit
- 有已暂存的变更 → 直接 commit
- 无变更但有未推送的 commit → 跳到 push
- 完全无变更 → 提示用户

### 4. Commit

从用户消息中提取 commit message。如果用户没有提供明确的 commit message，从变更内容自动生成一个简短的描述。

```bash
git add -A
git commit -m "<message>"
```

### 5. Push

```bash
# 推送到检测到的 remote（fork 模式下可能是 origin 或 xzx 等）
git push -u $PUSH_REMOTE <branch>
```

如果 push 被拒绝（remote 有新 commit），提示用户是否 rebase：
```bash
git pull --rebase $PUSH_REMOTE <branch>
git push $PUSH_REMOTE <branch>
```

### 6. 创建 PR（除非 --no-pr）

先检查是否已有 PR：

**fork 模式**：
```bash
gh pr list --repo $PR_REPO --head xzxiong:<branch> --state open --json number,url
```

**同仓库模式**：
```bash
gh pr list --repo $PR_REPO --head <branch> --state open --json number,url
```

- **已有 PR** → 输出 PR URL，不重复创建
- **无 PR** → 创建新 PR

创建 PR：

**fork 模式**：
```bash
gh pr create \
  --repo $PR_REPO \
  --base dev \
  --head xzxiong:<branch> \
  --title "<commit message 首行>" \
  --body ""
```

**同仓库模式**：
```bash
gh pr create \
  --repo $PR_REPO \
  --base dev \
  --head <branch> \
  --title "<commit message 首行>" \
  --body ""
```

### 7. 自动生成 PR 描述 + Code Review

PR 创建成功后（或已有 PR 时），**主代理自己**依次执行以下操作（不使用 subagent，避免权限审批问题）：

**Step 7a: 更新 PR 描述**

主代理直接执行 `update-pr-desc` skill 的逻辑：
1. 读取 PR 元数据和 diff（已在步骤 6 中获取了 PR URL）
2. 分析变更生成结构化描述
3. 通过 `gh api` REST 接口更新 PR body

**Step 7b: Code Review**（除非 `--no-review`）

PR 描述更新完成后，主代理直接执行 `review-pr` skill 的逻辑：
1. 获取 PR 元数据和 diff
2. 生成审查报告
3. 归档到 `~/pr_review/`
4. 发布为 PR comment

⚠️ **重要**：步骤 7a 和 7b 必须由主代理自己执行（读取对应 skill 文件获取指令），**不要委托给 subagent**。subagent 没有预授权的文件读取权限，会触发交互式审批，阻塞流程。

### 8. 输出结果

```
✅ Committed: <short sha> <message>
✅ Pushed: $PUSH_REMOTE (<fork-or-repo>) ← <branch>
✅ PR: https://github.com/$PR_REPO/pull/<number>
✅ PR Description: updated
✅ Code Review: posted to PR comment
```

## Gotchas

1. **保护分支**：`dev`、`main` 分支禁止直接 push，必须通过 PR。
2. **repo 名提取**：从 remote URL 中提取，支持 SSH（`git@github.com:owner/repo.git`）和 HTTPS（`https://github.com/owner/repo.git`）格式。
3. **head 格式**：fork 模式下 `--head` 必须带 `xzxiong:` 前缀。
4. **已有 PR**：如果当前分支已有 open PR，只 push 不重复创建。
5. **fork remote 名不固定**：不同仓库的 fork remote 名可能不同（`origin`、`xzx` 等），通过 URL 内容而非 remote 名判定。
