---
name: git-push-pr
description: |
  提交代码、推送分支、创建 PR 的一站式流程。Push 默认推到 xzxiong fork，PR 默认提到 matrixorigin 上游。

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

## 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| push remote | `origin` → `xzxiong/<repo>` | fork 仓库 |
| PR target repo | `matrixorigin/<repo>` | 上游仓库 |
| PR base branch | `dev` | 目标分支 |

用户可在消息中覆盖：
- `--base main` → PR 目标分支改为 main
- `--repo other-org/repo` → PR 目标仓库
- `--remote upstream` → push 到其他 remote
- `--no-pr` → 只 push 不创建 PR
- `--no-review` → 创建 PR 后跳过自动 review

## Skill 逻辑

### 1. 检查工作区状态

```bash
# 确认在 git 仓库中
git rev-parse --is-inside-work-tree

# 获取当前分支名
git branch --show-current

# 获取 repo 名（从 remote URL 提取）
git remote get-url origin
```

如果当前分支是 `dev` 或 `main`，**拒绝操作**并提示用户先创建 feature 分支。

### 2. 检查变更

```bash
git status --porcelain
```

- 有未暂存的变更 → `git add -A` 然后 commit
- 有已暂存的变更 → 直接 commit
- 无变更但有未推送的 commit → 跳到 push
- 完全无变更 → 提示用户

### 3. Commit

从用户消息中提取 commit message。如果用户没有提供明确的 commit message，从变更内容自动生成一个简短的描述。

```bash
git add -A
git commit -m "<message>"
```

### 4. Push

```bash
# 推送到 fork（默认 origin → xzxiong/<repo>）
git push origin <branch> --set-upstream
```

如果 push 被拒绝（remote 有新 commit），提示用户是否 rebase：
```bash
git pull --rebase origin <branch>
git push origin <branch>
```

### 5. 创建 PR（除非 --no-pr）

先检查是否已有 PR：
```bash
gh pr list --repo matrixorigin/<repo> --head xzxiong:<branch> --state open --json number,url
```

- **已有 PR** → 输出 PR URL，不重复创建
- **无 PR** → 创建新 PR

创建 PR：
```bash
gh pr create \
  --repo matrixorigin/<repo> \
  --base dev \
  --head xzxiong:<branch> \
  --title "<commit message 首行>" \
  --body ""
```

注意：body 留空，由后续步骤自动生成。

### 6. 自动生成 PR 描述 + Code Review

PR 创建成功后（或已有 PR 时），**主代理自己**依次执行以下操作（不使用 subagent，避免权限审批问题）：

**Step 6a: 更新 PR 描述**

主代理直接执行 `update-pr-desc` skill 的逻辑：
1. 读取 PR 元数据和 diff（已在步骤 5 中获取了 PR URL）
2. 分析变更生成结构化描述
3. 通过 `gh api` REST 接口更新 PR body

**Step 6b: Code Review**（除非 `--no-review`）

PR 描述更新完成后，主代理直接执行 `review-pr` skill 的逻辑：
1. 获取 PR 元数据和 diff
2. 生成审查报告
3. 归档到 `~/pr_review/`
4. 发布为 PR comment

⚠️ **重要**：步骤 6a 和 6b 必须由主代理自己执行（读取对应 skill 文件获取指令），**不要委托给 subagent**。subagent 没有预授权的文件读取权限，会触发交互式审批，阻塞流程。

### 7. 输出结果

```
✅ Committed: <short sha> <message>
✅ Pushed: xzxiong/<repo> ← <branch>
✅ PR: https://github.com/matrixorigin/<repo>/pull/<number>
✅ PR Description: updated
✅ Code Review: posted to PR comment
```

## Gotchas

1. **保护分支**：`dev`、`main` 分支禁止直接 push，必须通过 PR。
2. **repo 名提取**：从 `git remote get-url origin` 中提取，支持 SSH 和 HTTPS 格式。
3. **head 格式**：创建 PR 时 `--head` 必须带 fork owner 前缀，如 `xzxiong:feat/my-branch`。
4. **已有 PR**：如果当前分支已有 open PR，只 push 不重复创建。
