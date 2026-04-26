根据 PR review comments 自动修复代码并提交。

Input: $ARGUMENTS (PR URL 或 #number, 可选: --reviewer <name>, --unresolved-only)

默认行为：`--unresolved-only`（只处理未 resolved 的评论）。

## 流程

### 1. 确认工作区
```bash
git branch --show-current  # 确认与 PR head branch 一致
git status --porcelain
```
- **有未提交变更** → 快速提交模式：跳到 commit → push → 回复 comments
- **工作区干净** → 自动修复模式：完整流程

### 2. 获取 Review Comments（GraphQL）
```graphql
query { repository { pullRequest(number:) {
  reviewThreads(first: 100) { nodes {
    isResolved, isOutdated, path, line, startLine
    comments(first: 50) { nodes { id, author { login }, body, path, line } }
  }}
}}}
```

### 3. 筛选
- 默认只处理 `isResolved: false`
- 跳过 `isOutdated: true`
- 跳过纯讨论性评论（LGTM、提问等）
- 按文件分组，输出摘要供确认

### 4. 读取代码上下文
读取每个 comment 指向的文件。

### 5. 逐条修复
- 理解 reviewer 意图 → 定位代码 → 生成修复 → 应用 → 验证语法（`go vet ./...`）
- 支持 GitHub `suggestion` 代码块直接提取

### 6. Commit + Push
```bash
git add -A
git commit -m "fix: address review comments on PR #<number>"
git push origin <branch>
```

### 7. 回复 Review Comments
```graphql
mutation { addPullRequestReviewThreadReply(input: {
  pullRequestReviewThreadId: $threadId, body: "Fixed in <sha>."
}) { comment { id } }}
```

### 修复原则
1. 最小修改：只改 reviewer 指出的问题
2. 忠实意图：严格按建议修复
3. 保持一致：风格与项目一致
4. 安全优先：有风险的建议提示用户
5. 超过 20 条 comments 分批处理
