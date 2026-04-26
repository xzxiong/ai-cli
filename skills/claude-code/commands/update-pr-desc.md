根据 PR 实际代码变更，自动生成结构化 PR 描述并更新到 GitHub。

Input: $ARGUMENTS (PR URL 或 #number)

## 流程

### 1. 获取 PR 元数据
```bash
gh pr view <number> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state
```

### 2. 获取代码 diff
```bash
gh pr diff <number> 2>&1 | grep -n '^diff --git'
gh pr diff <number> 2>&1 | sed -n '<START>,<END>p'
```
跳过自动生成文件（swagger.json、docs.go）。优先读取业务逻辑（handler、service、model）。

### 3. 分析变更并生成描述

模板结构：
- **变更说明**：~100字概述 + 关键变更点列表
- **核心变更**：按模块分组
- **调用链/数据流**：
  - 单模块 → 函数调用链（ASCII 箭头，标注 `← NEW` / `← 修改`）
  - 跨模块 → 服务间数据流（ASCII 流程图）
  - 简单变更可省略
- **新增文件表格**
- **变更类型** checklist
- **影响范围** checklist（团队/测试/文档）
- **UT/BVT 覆盖说明**（有测试代码时必填）
- **相关链接**：⚠️ 从原始 PR body 中原样保留，不覆盖
- **环境验证** / **检查清单**

### 4. 更新 PR（使用 REST API）
```bash
cat > /tmp/pr-body.md << 'EOF'
...
EOF
gh api repos/<owner>/<repo>/pulls/<number> -X PATCH -F "body=@/tmp/pr-body.md"
rm /tmp/pr-body.md
```
⚠️ 不要用 `gh pr edit --body`，仓库启用 Projects Classic 时会静默失败。

### 5. 验证
```bash
gh pr view <number> --json body --jq '.body' | head -5
```
