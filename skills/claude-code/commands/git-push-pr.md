一站式完成：commit → push → create PR → update PR desc → code review。

Input: $ARGUMENTS (commit message, 可选 flags: --base main, --no-pr, --no-review)

## 仓库模式判定

扫描 `git remote -v`：
- 存在 `xzxiong/<repo>` 和 `matrixorigin/<repo>` 两个 remote → **fork 模式**（push 到 xzxiong remote，PR 到 matrixorigin）
- 否则 → **同仓库模式**（push 到 origin）
- 白名单走同仓库模式：matrixone-operator

## 流程

### 1. 检查状态
```bash
git branch --show-current  # 禁止在 dev/main 上直接操作
git status --porcelain
```

### 2. Commit
- 有未暂存变更 → `git add -A` → commit
- 有已暂存变更 → 直接 commit
- 无变更但有未推送 commit → 跳到 push
- 完全无变更 → 提示用户

### 3. Push
```bash
git push -u $PUSH_REMOTE <branch>
```
被拒绝时提示 rebase：`git pull --rebase $PUSH_REMOTE <branch>`

### 4. 创建 PR（除非 --no-pr）
先检查已有 PR：
- fork: `gh pr list --repo $PR_REPO --head xzxiong:<branch> --state open --json number,url`
- 同仓库: `gh pr list --repo $PR_REPO --head <branch> --state open --json number,url`

已有 → 输出 URL，不重复创建。无 PR → 创建：
- fork: `gh pr create --repo $PR_REPO --base dev --head xzxiong:<branch> --title "<msg>" --body ""`
- 同仓库: `gh pr create --repo $PR_REPO --base dev --head <branch> --title "<msg>" --body ""`

### 5. 更新 PR 描述
按 `/update-pr-desc` skill 的逻辑：获取 diff → 分析变更 → 生成结构化描述 → `gh api repos/.../pulls/<number> -X PATCH -F "body=@/tmp/pr-body.md"`

### 6. Code Review（除非 --no-review）
按 `/review-pr` skill 的逻辑：获取 diff → 生成审查报告 → 归档到 `~/pr_review/` → 发布为 PR comment

### 输出
```
✅ Committed: <sha> <message>
✅ Pushed: <remote> ← <branch>
✅ PR: <url>
✅ PR Description: updated
✅ Code Review: posted
```
