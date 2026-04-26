从当前修改出发：创建新分支 → commit → push → 创建 PR → 更新描述 → code review。

Input: $ARGUMENTS (commit message, 可选: --base main, --branch <name>, --no-review)

## 仓库模式判定

扫描 `git remote -v`：
- 存在 `xzxiong/<repo>` 和 `matrixorigin/<repo>` → **fork 模式**
- 否则 → **同仓库模式**
- 白名单走同仓库模式：matrixone-operator

## 流程

### 1. 检查变更
```bash
git status --porcelain
```
无变更 → 提示用户，终止。

### 2. 确定分支名
用户指定 `--branch` 则使用它，否则从 commit message 自动生成：
- `fix: 修复xxx` → `fix/修复xxx`
- `feat: add export` → `feat/add-export`
规则：`<type>/<summary>`，空格替换为 `-`，截断 50 字符。

### 3. 创建分支并 Commit
当前在主分支 → `git checkout -b <new-branch>`，然后 `git add -A && git commit -m "<msg>"`
当前在 feature 分支 → 直接 commit

### 4. Push
```bash
git push -u $PUSH_REMOTE <branch>
```

### 5. 创建 PR
检查已有 PR，无则创建。fork 模式 `--head xzxiong:<branch>`。

### 6. 更新 PR 描述 + Code Review
同 `/git-push-pr` 的步骤 5-6。

### 输出
```
✅ Branch: <branch>
✅ Committed: <sha> <message>
✅ Pushed: <remote> ← <branch>
✅ PR: <url>
✅ PR Description: updated
✅ Code Review: posted
```
