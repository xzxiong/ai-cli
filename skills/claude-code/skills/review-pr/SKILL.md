---
name: review-pr
description: |
  对 PR 进行全面 Code Review，输出结构化审查报告（中文）。支持三种模式：
  - 标准模式（默认）：面向成熟方案，全面审查代码质量、测试、性能、安全、LLM Prompt 等
  - 探索模式（`--explore`）：面向 Demo/PoC，侧重方案梳理、逻辑自洽、可观测性、可迭代性
  - Ops 模式（`--ops` 或自动识别）：面向基础设施/部署仓库，侧重资源配置、安全、影响范围

  Use this skill when:
  - The user says "review pr" followed by a PR URL or number
  - The user invokes `/review-pr <PR_URL>` or `/review-pr #<number>`
  - The user says "review"、"代码审查"、"看下这个 PR" with a PR URL or number
  - The user says "review pr --explore" or "探索性review" for exploratory/demo PRs
  - The user says "review pr --ops" or PR is from ops/gitops/moi-gitops/moi-op repos
---

# Review PR

对 PR 进行全面 Code Review，输出结构化审查报告（中文）。

## 输入

`$ARGUMENTS`：PR URL 或 `#number`，可选 flag：`--explore`、`--ops`、`--with-issue`

## 模式判断

1. `--explore` → 探索模式
2. `--ops` → Ops 模式
3. PR 来自 `ops`/`gitops`/`moi-gitops`/`moi-op` 仓库 → Ops 模式（自动识别）
4. 否则 → **标准模式**

## 执行流程

### Step 1. 获取 PR 数据

```bash
# 元数据
gh pr view <number> --repo <OWNER/REPO> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state,author

# Diff 文件索引
gh pr diff <number> --repo <OWNER/REPO> 2>&1 | grep -n '^diff --git'

# 按需分段读取 diff（跳过 swagger.json / docs.go 等自动生成文件）
gh pr diff <number> --repo <OWNER/REPO> 2>&1 | sed -n '<START>,<END>p'
```

**读取优先级**：业务逻辑（handler/service/processor） > schema/model > 配置 > 测试 > 文档

### Step 2. 获取关联 Issue（仅 `--with-issue` 时）

从 PR body/commit message 提取 issue 编号：
```bash
gh issue view <number> --repo <OWNER/REPO> --json title,body
gh api repos/<OWNER>/<REPO>/issues/<number>/comments --jq '.[].body'
```

### Step 3. 确定模式，Read 对应 checklist

根据模式判断结果，Read 对应的详细 checklist 文件作为审查指引：

- **标准模式** → Read `~/.claude/skills/review-pr/references/standard-checklist.md`
- **探索模式** → Read `~/.claude/skills/review-pr/references/explore-checklist.md`
- **Ops 模式** → Read `~/.claude/skills/review-pr/references/ops-checklist.md`

### Step 4. 生成审查报告

按 checklist 中的报告模板逐章生成。每条 issue 用 `<a id="issue-N"></a>` 锚点，引用处用 `[🔴 #N](#issue-N)` 链接。

代码审查分级：
- 🔴 必须修改（bug/严重问题）
- 🟡 建议修改（质量/可维护性）
- 🟢 可选优化

### Step 5. 归档

保存到 `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`。
已存在则重命名旧文件为 `_bakNNN.md` 保留（NNN 从 001 递增）。

### Step 6. 折叠历史审查评论

```bash
# 获取当前用户
CURRENT_USER=$(gh api user --jq '.login')

# 查找并折叠旧评论（特征：body 以 "# Code Review:" 开头或含 "## 〇、总结（TL;DR）"）
gh api graphql -f query='...'  # minimizeComment(classifier: OUTDATED)
```

仅折叠当前用户的、未折叠的、匹配特征的评论。

### Step 7. 发布

```bash
gh pr comment <number> --repo <OWNER/REPO> --body-file <归档md路径>
```

## 审查原则

1. **务实导向**：只提有价值的建议，不吹毛求疵
2. **给出方案**：每个问题附带具体修复建议或代码示例
3. **分清主次**：严重问题优先，风格问题次之
4. **理解意图**：结合 PR 目的和上下文评审
5. **中文输出**：报告全程中文

## Gotchas

1. 大 PR 先用 `grep -n` 定位文件边界，按需 `sed -n` 读取，避免 context 溢出
2. swagger.json / docs.go / generated 文件跳过
3. 私有仓库必须用 `gh` CLI（不能 web_fetch）
4. diff 不足以判断时用 `gh api` 获取完整文件辅助
5. 二进制文件（.png/.pdf）跳过 diff，仅确认存在
