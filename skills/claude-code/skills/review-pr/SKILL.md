---
name: review-pr
description: |
  对 PR 进行全面 Code Review，输出结构化审查报告（中文）。支持多种模式：
  - 标准模式（默认）：面向成熟方案，全面审查代码质量、测试、性能、安全、LLM Prompt 等
  - Fast 模式（`--fast`）：高信号静态审查，不跑测试/CI，快速给出可证实问题
  - 探索模式（`--explore`）：面向 Demo/PoC，侧重方案梳理、逻辑自洽、可观测性、可迭代性
  - Ops 模式（`--ops` 或自动识别）：面向基础设施/部署仓库，侧重资源配置、安全、影响范围

  Use this skill when:
  - The user says "review pr" followed by a PR URL or number
  - The user invokes `/review-pr <PR_URL>` or `/review-pr #<number>`
  - The user says "review"、"代码审查"、"看下这个 PR" with a PR URL or number
  - The user says "review pr --fast" / "fast review" / "快速 review" for static-only review
  - The user says "review pr --explore" or "探索性review" for exploratory/demo PRs
  - The user says "review pr --ops" or PR is from ops/gitops/moi-gitops/moi-op/ob-ops repos
---

# Review PR

对 PR 进行全面 Code Review，输出结构化审查报告（中文）。先选择模式，再以具体发现为主，不要先写空泛摘要。

## 输入

`$ARGUMENTS`：PR URL 或 `#number`，可选 flag：`--fast`、`--explore`、`--ops`、`--with-issue`

## 模式

- **标准模式**（默认）：面向成熟方案，全面审查代码质量、测试、性能、安全、LLM Prompt 等
- **Fast 模式**（`--fast`）：高信号静态审查，快速反馈。不跑测试、不触发/重试 CI、不等待测试结果，不加载完整测试方案 checklist。基于 diff 与必要周边代码审查正确性、安全、兼容性、配置风险。可读测试文件作为代码上下文，但报告必须写明“测试未执行”，且不得声称测试验证通过
- **探索模式**（`--explore`）：面向 Demo/PoC，侧重方案梳理、逻辑自洽、可观测性、可迭代性
- **Ops 模式**（`--ops` 或自动识别）：面向基础设施/部署仓库，侧重资源配置、安全、影响范围

## 模式判断

1. `--fast` → Fast 模式（显式优先于自动模式识别）
2. `--explore` → 探索模式
3. `--ops` → Ops 模式
4. PR 来自 `ops`/`gitops`/`moi-gitops`/`moi-op`/`ob-ops` 仓库 → Ops 模式（自动识别）
5. 否则 → **标准模式**

不要把 `--fast` 与 `--explore` / `--ops` 组合使用；若 flag 冲突，先请用户选一种模式。

## 深度开关（标准模式内）

标准模式下，根据 PR 特征自动决定 2.2/2.3 章节是否展开：

- **2.2 架构评审**：当满足以下任一条件时展开（否则标「不适用」跳过）
  - 新增 ≥3 个源码文件
  - 大量代码从一个文件移动到多个文件（deletions 占比 > 40% 且有对应新增文件）
  - PR 标题/描述含 refactor / restructure / 重构 / 拆分
  - 涉及类型定义文件的新增或大幅重写

- **2.3 存量适配影响**：当满足以下任一条件时展开（否则标「不适用」跳过）
  - 有导出函数/类型被删除或签名变更
  - 有 JSON struct tag 的字段删除/重命名
  - 有 form/template/config 的 field_id 或 key 变更
  - PR 描述提及「向后兼容」「存量」「迁移」或 deletions > 500

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

### Step 2. 提取设计文档

**始终执行**。从以下位置搜索设计文档/方案描述（按优先级）：

1. **PR body**：查找「设计文档」「方案」「设计」「design」链接或内联描述
2. **关联 Issue**：从 PR body / commit message 提取 issue 编号，获取 issue body + comments
3. **PR comment**：查看是否有作者补充的方案说明 comment

```bash
# 从 PR body 提取 issue 编号（匹配 #123、fixes #123、closes #123、issue链接等）
# 如发现 issue 编号：
gh issue view <number> --repo <OWNER/REPO> --json title,body
gh api repos/<OWNER>/<REPO>/issues/<number>/comments --jq '.[].body'

# 检查 PR comments 是否有设计补充
gh api repos/<OWNER>/<REPO>/issues/<number>/comments --jq '.[] | select(.author_association == "MEMBER" or .author_association == "OWNER") | .body' | head -50
```

**结果处理**：
- 找到设计文档 → 后续方案评审时对照设计文档验证实现是否一致，偏差处标注
- 未找到 → 在报告「一、PR 描述评审」中输出 `⚠️ 未找到设计文档/方案描述`，提醒作者补充，但继续 review（基于代码本身推断意图）

### Step 3. 确定模式，Read 对应 checklist

根据模式判断结果，Read 对应的详细 checklist 文件作为审查指引：

- **Fast 模式** → Read `~/.claude/skills/review-pr/references/fast-checklist.md`
  - 不执行测试命令，不触发/重试 CI，不等待测试结果
  - 不读取 `section-testing.md`
  - 仅使用 fast checklist；报告必须显式写出“测试未执行”
- **标准模式** → Read `~/.claude/skills/review-pr/references/standard-checklist.md`（骨架）
  - 始终 Read：`section-testing.md`、`section-risks.md`
  - 条件触发 Read：`section-architecture.md`（满足深度开关条件时）
- **探索模式** → Read `~/.claude/skills/review-pr/references/explore-checklist.md`
- **Ops 模式** → Read `~/.claude/skills/review-pr/references/ops-checklist.md`

### Step 4. 生成审查报告

按 checklist 中的报告模板逐章生成。每条 issue 用 `<a id="issue-N"></a>` 锚点，引用处用 `[🔴 I-N](#issue-N)` 链接。

**⚠️ 编号格式**：使用 `I-N`（如 `I-1`、`I-2`）而非 `#N`。GitHub 会将 `#数字` 解析为 issue/PR 链接，导致错误关联。

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

# 查找并折叠旧评论（特征：body 以 "# Code Review:" / "# Fast Review:" 开头，或含 "## 〇、总结（TL;DR）"）
gh api graphql -f query='...'  # minimizeComment(classifier: OUTDATED)
```

仅折叠当前用户的、未折叠的、匹配特征的评论。

### Step 7. 发布

```bash
gh pr comment <number> --repo <OWNER/REPO> --body-file <归档md路径>
```

### Step 8. 按合并建议提交 Review 决议

发布评论后，**必须**根据报告「〇、总结（TL;DR）」中的**合并建议**提交 GitHub PR review（不只留言）：

| 合并建议（报告原文） | GitHub review 动作 | 命令 |
|----------------------|--------------------|------|
| **建议合并** | `APPROVE` | `gh pr review <number> --repo <OWNER/REPO> --approve --body "<短评>"` |
| **修复后合并** | `REQUEST_CHANGES` | `gh pr review <number> --repo <OWNER/REPO> --request-changes --body "<短评>"` |
| **需要重大修改** | `REQUEST_CHANGES` | 同上 |
| 其他 / 无法判断 | `COMMENT`（仅评论，不 approve 也不 request changes） | `gh pr review <number> --repo <OWNER/REPO> --comment --body "<短评>"` |

**短评模板**（`--body`，与 Step 7 长报告互补，保持简短）：

```text
# 建议合并（标准 / 探索 / Ops）
Code Review 通过：无 🔴 必须修改项。详情见上方审查评论。

# 建议合并（Fast）
静态审查通过：无 🔴 必须修改项（测试未执行）。详情见上方审查评论。

# 修复后合并 / 需要重大修改
请求修改：存在 🔴 必须修改项（或方案需重大调整），修复后再 merge。
要点：
- I-1: <一句话>
- I-2: <一句话>
详情见上方审查评论。
```

**规则**：
1. **以报告合并建议为准**，不要只数 🔴 条数自行改判；若建议与 🔴 不一致，先修正报告建议再提交 review。
2. **常规映射**：无 🔴 → 建议合并 → approve；有 🔴 → 修复后合并 → request changes；方案推倒级问题 → 需要重大修改 → request changes。
3. **Fast 模式额外要求**：若报告建议合并，短评与报告 TL;DR 都必须写明“基于静态审查，测试未执行”。
4. **幂等（所有 Step 8 决议，不只 approve）**：
   - Step 8 对同一 `head SHA` **默认只提交一次** `APPROVE` / `CHANGES_REQUESTED` / `COMMENTED`。
   - **任何** Step 8 调用之前（含误判失败后的重试），必须先查当前用户在该 PR 上的 reviews；不得凭「没看到成功回显」直接重跑。
   - 若同用户在**当前 head SHA** 上已有**相同决议状态**的 review（含刚刚提交的），**禁止再提一条同决议**；直接结束 Step 8。
   - 仅当合并建议相对已有决议**发生变化**（例如 APPROVE → REQUEST_CHANGES，或反之）时，才允许再提一条新的 `gh pr review` 覆盖（GitHub 以最新为准）。
   - Step 7（`gh pr comment`）与 Step 8（`gh pr review`）是两次独立 API；comment 成功**不代表** review 未发出。二者可分两条 shell 执行，便于各自确认退出码。
5. **权限失败**：若 `APPROVE` / `REQUEST_CHANGES` 因权限或 branch protection 失败，在对用户的回复中说明，并保留 Step 7 评论；不要静默跳过。失败后若要重试，仍须先走规则 4 的预检查。
6. **草稿 PR / 已关闭 / 已合并**：跳过 Step 8，仅在回复中说明原因。
7. **自己的 PR**：GitHub 不允许 self-approve；若 `author.login` 是当前用户，跳过 approve，可仍 `request changes` 或只 comment。
8. 批量 review 多个 PR 时，**每个 PR 独立**执行 Step 7 + Step 8。

```bash
# Step 8 预检查（每次提交/重试前必跑；把期望状态换成 APPROVED / CHANGES_REQUESTED / COMMENTED）
# 注意：`gh api --jq` 不支持 jq 的 `--arg`；用 shell 变量插值，或 `gh api ... | jq --arg ...`。
OWNER=<OWNER>; REPO=<REPO>; NUMBER=<number>
HEAD_SHA=$(gh api "repos/$OWNER/$REPO/pulls/$NUMBER" --jq .head.sha)
ME=$(gh api user --jq .login)
EXPECTED=CHANGES_REQUESTED   # 或 APPROVED / COMMENTED
EXISTING=$(gh api "repos/$OWNER/$REPO/pulls/$NUMBER/reviews" \
  --jq "[.[] | select(.user.login==\"$ME\" and .commit_id==\"$HEAD_SHA\" and .state==\"$EXPECTED\")] | length")
if [ "$EXISTING" -gt 0 ]; then
  echo "Skip Step 8: $ME already has $EXPECTED on $HEAD_SHA"
  exit 0
fi

# 示例：建议合并（标准）
gh pr review <number> --repo <OWNER/REPO> --approve --body "Code Review 通过：无 🔴 必须修改项。详情见上方审查评论。"

# 示例：建议合并（Fast）
gh pr review <number> --repo <OWNER/REPO> --approve --body "静态审查通过：无 🔴 必须修改项（测试未执行）。详情见上方审查评论。"

# 示例：修复后合并
gh pr review <number> --repo <OWNER/REPO> --request-changes --body "$(cat <<'EOF'
请求修改：存在 🔴 必须修改项，修复后再 merge。
要点：
- I-1: <摘要>
详情见上方审查评论。
EOF
)"
```

## 审查原则

1. **务实导向**：只提有价值的建议，不吹毛求疵
2. **给出方案**：每个问题附带具体修复建议或代码示例
3. **分清主次**：严重问题优先，风格问题次之
4. **理解意图**：结合 PR 目的和上下文评审
5. **中文输出**：报告全程中文
6. **证据优先**：每条发现尽量带文件/行证据、行为影响和可操作修复

## Gotchas

1. 大 PR 先用 `grep -n` 定位文件边界，按需 `sed -n` 读取，避免 context 溢出
2. swagger.json / docs.go / generated 文件跳过
3. 私有仓库必须用 `gh` CLI（不能 web_fetch）
4. diff 不足以判断时用 `gh api` 获取完整文件辅助
5. 二进制文件（.png/.pdf）跳过 diff，仅确认存在
6. Fast 模式禁止执行测试/CI 验证动作；可读测试文件，但不能据此声称测试通过
7. Step 7/8 不要因「只看到 `ok commented`」就重跑 `gh pr review`：`gh pr review` 成功时常无同等醒目回显；合并进同一条 shell 时更容易误判。重试前必须按 Step 8 规则 4 查同 SHA 是否已有相同决议（matrixflow#16956 曾因此对同一 head 提交两条相同的 `CHANGES_REQUESTED`）
