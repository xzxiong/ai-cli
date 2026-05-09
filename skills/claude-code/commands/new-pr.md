从当前修改出发：创建新分支 → commit → push → 创建 PR → 更新描述 → code review。Trigger on: "new pr", "开 pr", "提 pr", "create pr", "open pr", "submit pr", "提交 pr", "pr 一下", "推个 pr", "发 pr", or any request to create/open a pull request from current local changes.

Input: $ARGUMENTS (commit message, 可选: --base <branch>, --branch <name>, --no-review)

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

**已知同仓库模式白名单**（即使存在 fork remote 也走同仓库模式）：
- matrixone-operator

**仓库默认 base 分支**（不同仓库主分支不同）：

| 仓库 | 默认 base 分支 |
|------|---------------|
| `matrixflow` | `dev` |
| `moi-frontend` | `dev` |
| 其他 | `main`（若存在 `master` 则用 `master`） |

用户通过 `--base` 参数可覆盖。

## 流程

### 1. 检查工作区状态
```bash
git rev-parse --is-inside-work-tree
CURRENT_BRANCH=$(git branch --show-current)
git status --porcelain
```
无变更 → 提示用户，终止。

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
  # 检查是否在同仓库模式白名单中
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

# 确定默认 base 分支（用户 --base 参数优先）
if [[ -z "$BASE_BRANCH" ]]; then
  case "$REPO_NAME" in
    matrixflow|moi-frontend) BASE_BRANCH="dev" ;;
    *)
      # 检测远端是否有 main 或 master
      if git ls-remote --heads "$PUSH_REMOTE" main 2>/dev/null | grep -q main; then
        BASE_BRANCH="main"
      else
        BASE_BRANCH="master"
      fi
      ;;
  esac
fi
```

### 3. 确定分支名
用户指定 `--branch` 则使用它，否则从 commit message 自动生成：
- `fix: 修复删除线检测` → `fix/修复删除线检测`
- `feat: add export API` → `feat/add-export-API`

规则：取 `<type>/<summary>`，空格替换为 `-`，截断到 50 字符。

### 4. 创建分支并 Commit
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

### 5. Push
```bash
# 推送到检测到的 remote（fork 模式下可能是 origin 或其他名称）
git push -u $PUSH_REMOTE <branch>
```

### 6. 创建 PR
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
  --base $BASE_BRANCH \
  --head xzxiong:<branch> \
  --title "<commit message>" \
  --body ""
```

**同仓库模式**：
```bash
gh pr create \
  --repo $PR_REPO \
  --base $BASE_BRANCH \
  --head <branch> \
  --title "<commit message>" \
  --body ""
```

### 7. 更新 PR 描述
PR 创建成功后，通过 `gh api` 更新 PR body：

1. 读取 commit history: `git log upstream/$BASE_BRANCH..HEAD` (或 `origin/$BASE_BRANCH..HEAD`)
2. 分析代码变更: `git diff upstream/$BASE_BRANCH...HEAD`
3. 生成结构化描述：
   - Summary: 简要概述（1-2 句话）
   - 功能特性/变更内容
   - 技术实现
   - 测试
   - Checklist
4. 更新 PR: `gh api --method PATCH /repos/$PR_REPO/pulls/$PR_NUMBER -f body="..."`

### 8. Code Review（除非 --no-review）
生成审查报告并发布为 PR comment：

1. 读取变更文件和 diff
2. 分析代码质量、安全性、最佳实践
3. 生成结构化 review：
   - 变更概览
   - 优点
   - 建议（按优先级）
   - 关键审查点
   - 总体评价
4. 发布 comment: `gh pr comment $PR_NUMBER --body "..."`

⚠️ 步骤 7 和 8 必须由主代理自己执行，不要委托给 subagent。

### 输出
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
