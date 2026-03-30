---
name: review-fix
description: |
  根据 PR review comments 自动修复代码并提交 commit。读取 reviewer 的评论，定位问题代码，执行修复，提交并推送。

  Use this skill when:
  - The user says "review fix" followed by a PR URL or number
  - The user invokes `/review-fix <PR_URL>`
  - The user says "修复review" or "fix review" with a PR URL or number
  - The user says "fix comments" or "修复评论" with a PR URL or number
  - The user says "review push" or "commit push review" with a PR URL or number
---

# Review Fix Skill

## 目的
根据 PR 上 reviewer 的 review comments，自动修复代码并提交 commit。

## 使用方法
```bash
kiro chat "review fix https://github.com/matrixorigin/matrixflow/pull/8638"
kiro chat "review fix #8638"
kiro chat "修复review #8638"

# 可选：只修复特定 reviewer 的评论
kiro chat "review fix #8638 --reviewer alice"

# 可选：只修复未 resolved 的评论
kiro chat "review fix #8638 --unresolved-only"
```

默认行为：`--unresolved-only`（只处理未 resolved 的评论）。

## 默认配置

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| push remote | `origin` | fork 仓库 |
| PR target repo | `matrixorigin/<repo>` | 上游仓库 |
| 过滤 | `--unresolved-only` | 默认只处理未 resolved 的 review comments |

## Skill 逻辑

### 1. 确认工作区状态

```bash
# 确认在 git 仓库中
git rev-parse --is-inside-work-tree
git status --porcelain
git branch --show-current
```

- 获取当前分支名，确认与 PR head branch 一致。如果不一致，提示用户切换分支。
- 检查工作区是否有未提交的变更（`git status --porcelain`）。

**两种模式：**

- **有未提交变更** → 进入「快速提交模式」：跳过步骤 2-5，直接执行步骤 6（commit）→ 7（push）→ 8（回复 comments）。根据 `git diff` 的内容自动生成 commit message，并匹配对应的 unresolved review comments 进行回复。
- **工作区干净** → 进入「自动修复模式」：执行完整流程（步骤 2-8），分析 review comments 并自动修复代码。

### 2. 获取 PR Review Comments

使用 GraphQL 获取 PR 的所有 review comments（包括 review thread 的 resolved 状态）：

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      title
      headRefName
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          isResolved
          isOutdated
          path
          line
          startLine
          diffSide
          comments(first: 50) {
            nodes {
              id
              author { login }
              body
              createdAt
              path
              line
              startLine
            }
          }
        }
      }
    }
  }
}' -f owner=<OWNER> -f repo=<REPO> -F pr=<PR_NUMBER>
```

### 3. 筛选需要修复的 Comments

按以下规则筛选：

1. **默认只处理未 resolved 的 thread**（`isResolved: false`）
2. **跳过 outdated 的 thread**（`isOutdated: true`，代码已变更）
3. **如果指定了 `--reviewer`**，只处理该 reviewer 的评论
4. **跳过纯讨论性评论**：通过启发式判断排除不需要代码修改的评论（如 "LGTM"、"看起来不错"、纯提问等）
5. **识别可操作的评论**：包含代码建议、修改要求、bug 指出等

对筛选后的 comments，按文件分组，输出摘要供用户确认：

```
📋 找到 N 条待修复的 review comments：

文件: pkg/handler/extract.go
  1. [alice] L45-52: 建议添加 nil check（🔴 必须修改）
  2. [bob] L120: 变量命名不清晰（🟡 建议修改）

文件: pkg/service/ocr.go
  3. [alice] L30: 错误处理缺失（🔴 必须修改）

是否全部修复？(Y/n/选择编号)
```

用户可以：
- 回车或 `Y` → 全部修复
- 输入编号如 `1,3` → 只修复选中的
- `n` → 取消

### 4. 读取相关代码上下文

对每个待修复的 comment，读取对应文件的相关代码：

```bash
# 读取 comment 指向的文件
cat <file_path>

# 如果 comment 引用了其他文件或函数，也一并读取
# 通过分析 comment body 中的代码引用来判断
```

### 5. 逐条修复

按文件分组，逐条修复 review comments：

对每条 comment：
1. 理解 reviewer 的意图（修复 bug、改进代码质量、添加错误处理等）
2. 定位需要修改的代码位置
3. 生成修复代码
4. 应用修改（使用 `fs_write` 的 `str_replace`）
5. 验证修改不会引入语法错误

```bash
# 修改后检查语法（Go 项目）
cd <repo_root> && go vet ./...
```

如果修复涉及多个文件的关联修改（如接口变更），一并处理。

### 6. 汇总修复并 Commit

所有修复完成后，生成一个汇总 commit：

```bash
git add -A
git diff --cached --stat

# commit message 格式：
# fix: address review comments on PR #<number>
#
# - <file1>: <修复摘要1>
# - <file2>: <修复摘要2>
# ...
git commit -m "fix: address review comments on PR #<number>

<逐条修复摘要>"
```

### 7. Push

```bash
git push origin <branch>
```

### 8. 回复 Review Comments（可选）

修复完成后，对每条已修复的 review thread 回复确认。回复内容需关联当前修复的具体问题：

```bash
# 对每个已修复的 review thread 回复，感谢 reviewer 并说明具体修复内容
gh api graphql -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}' -f threadId=<THREAD_ID> -f body="Thanks @<reviewer_login> for the review! Fixed in <commit_sha_short>."
```

### 9. 输出结果

```
✅ 修复完成！

📝 Commit: <short_sha> fix: address review comments on PR #<number>
📤 Pushed: origin/<branch>

修复明细：
  ✅ [1] pkg/handler/extract.go L45-52: 添加了 nil check
  ✅ [2] pkg/handler/extract.go L120: 重命名变量 x → extractResult
  ✅ [3] pkg/service/ocr.go L30: 添加错误处理和日志

💬 已回复 3 条 review comments
```

## 修复原则

1. **最小修改**：只修改 reviewer 指出的问题，不做额外重构
2. **忠实意图**：严格按照 reviewer 的建议修复，不自作主张
3. **保持一致**：修复代码风格与项目现有代码保持一致
4. **安全优先**：如果 reviewer 的建议可能引入新问题，提示用户而非盲目执行
5. **逐条确认**：修复前展示计划，让用户有机会调整

## Gotchas

1. **分支一致性**：必须确认当前本地分支与 PR head branch 一致，否则修复会提交到错误分支。
2. **代码冲突**：如果本地代码与 PR 最新版本不一致，先 `git pull --rebase` 同步。
3. **review thread ID**：回复 comment 需要 thread ID（非 comment ID），通过 GraphQL `reviewThreads` 获取。
4. **大量 comments**：如果 comments 超过 20 条，分批处理，每批修复后 commit 一次。
5. **suggestion 代码块**：GitHub review comment 中的 ````suggestion` 代码块可以直接提取为修复代码。
