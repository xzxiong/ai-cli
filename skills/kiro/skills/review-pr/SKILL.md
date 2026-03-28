---
name: review-pr
description: |
  对 PR 进行全面 Code Review：概述变更内容、提出更优方案建议、逐文件审查代码质量、检查并发/性能/成本等潜在问题。

  Use this skill when:
  - The user says "review pr" followed by a PR URL or number
  - The user invokes `/review-pr <PR_URL>`
  - The user says "review" or "代码审查" with a PR URL or number

  **Agent**: Uses `review-pr-agent` for analysis. The main agent MUST fetch all PR data first (the subagent has no bash access), then pass the data as `relevant_context` to the subagent.
---

# Review PR Skill

## 目的
对 PR 进行全面 Code Review，输出结构化的审查报告。

## 使用方法
```bash
kiro chat "review pr https://github.com/matrixorigin/matrixflow/pull/<PR_NUMBER>"
# 或
kiro chat "review pr #<PR_NUMBER>"

# 可选：关联 Issue 一起评审
kiro chat "review pr #<PR_NUMBER> --with-issue"
```

## Skill 逻辑

### ⚠️ 重要：执行模式

`review-pr-agent` 没有 bash 执行权限。主代理必须：
1. 自己执行所有 `gh` CLI 命令获取 PR 数据
2. 将获取到的数据（元数据 + diff）作为 `relevant_context` 传递给 `review-pr-agent`
3. 让 `review-pr-agent` 仅负责分析和生成报告

### 1. 获取 PR 元数据（主代理执行）
```bash
gh pr view <PR_NUMBER> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state
```

### 2. 获取代码 diff（主代理执行）
```bash
# 文件列表及 diff 位置索引
gh pr diff <PR_NUMBER> 2>&1 | grep -n '^diff --git'

# 按需读取核心代码变更（跳过生成文件如 swagger/docs）
gh pr diff <PR_NUMBER> 2>&1 | sed -n '<START>,<END>p'
```

注意：
- 跳过自动生成文件（swagger.json、docs.go 等）
- 大 PR 先定位文件边界，按需读取关键文件 diff
- 优先读取业务逻辑代码（handler、service、model、repo）

### 3. 获取关联 Issue（可选，需用户明确要求）
仅当用户在发起 review 时指定了 `--with-issue` 或明确要求"关联 Issue 一起看"时才执行。默认不获取。

从 PR body 或 commit message 中提取 issue 编号：
```bash
gh issue view <ISSUE_NUMBER> --json title,body
gh api repos/<OWNER>/<REPO>/issues/<ISSUE_NUMBER>/comments --jq '.[].body'
```

### 4. 委托 review-pr-agent 生成审查报告

将步骤 1-3 收集的所有数据作为 `relevant_context` 传递给 `review-pr-agent`，让其生成审查报告。

按以下维度输出结构化报告：

---

#### PR 基础信息（报告头部, follow the title）

在报告最前面输出 PR 的基础元数据，方便快速定位。格式如下：

```markdown
<!-- PR 基础信息 -->
- **PR**: [#<number> <title>](<pr_url>)
- **分支**: `<head>` → `<base>` | **变更**: +<additions> / -<deletions>，<file_count> 个文件
- **作者**: <author(s)> | **关联 Issue**: #<number> <title>（多个 issue 时只列编号如 #123 #456，无 issue 则省略后半段）
- **标签**: <labels>（无则省略此行）
```

---

#### 〇、总结（TL;DR）

放在报告最前面，让读者 30 秒内掌握全貌：
- 一句话概括 PR 做了什么
- 发现的问题统计（🔴 / 🟡 / 🟢 各多少条）
- 🔴 必须修改的问题摘要列表（每条一行）
- PR 描述质量：一句话总结描述是否完整，哪些维度缺失
- 合并建议（建议合并 / 修复后合并 / 需要重大修改）

#### 一、PR 描述评审（背景 / 原因 / 方案 / 结果）

对 PR body（以及关联 Issue body，如有）进行描述质量评审。PR 描述是 Reviewer 理解变更的第一入口，质量直接影响 Review 效率和准确性。

> 评审范围：默认仅评审 PR body。若用户要求关联 Issue，则将 Issue body 及其所有 comments 一并纳入评审（comments 中常包含方案讨论、技术决策等关键信息）。

**背景（Context）**
- 是否清晰描述了当前现状和上下文？
- 读者能否仅凭描述理解问题所处的业务/技术场景？

**原因（Why）**
- 是否说明了为什么要做这件事？驱动力是什么（用户反馈、性能瓶颈、技术债、新需求）？
- 问题的严重程度和影响范围是否有数据支撑？

**方案（How）**
- 是否描述了具体的技术方案或实现思路？
- 方案是否足够详细，能指导 Review（而非仅一句话概括）？
- 是否讨论了备选方案及取舍理由？

**结果（Expected Outcome）**
- 是否明确了预期结果和验收标准？
- 是否有可衡量的成功指标（性能提升 X%、错误率降至 Y 等）？

输出格式：
- ✅ 描述充分的维度 + 简要说明
- 🟡 描述不足的维度 + 缺少什么 + 建议补充的内容
- 🔴 完全缺失的维度 + 为什么需要补充

#### 二、变更概述（PR 做了什么）

用 2-3 段话概述：
- 这个 PR 的背景和目的
- 核心变更内容（按模块分组）
- 影响范围

#### 三、方案评审（是否有更优方案）

评估当前实现方案，考虑：
- 是否有更简洁的实现方式
- 是否有更高效的算法或数据结构
- 是否有可复用的现有组件/库被忽略
- 架构设计是否合理（职责划分、抽象层次）
- 是否过度设计或设计不足

**测试方案梳理**（UT / BVT / Eval）

对 PR 中的测试变更进行方案级评审，不仅看"有没有测试"，更要看"测试方案是否合理"：

**UT（单元测试）方案**
- 测试边界是否清晰？是否只测了被改动的最小单元，而非间接依赖？
- mock 策略是否合理？是否 mock 了正确的层（外部依赖 vs 内部实现细节）？
- 是否覆盖了核心分支：happy path、error path、边界值、空值/零值？
- 如果 PR 未包含 UT：评估哪些新增/修改的函数需要补充 UT，给出具体建议

**BVT（集成/端到端测试）方案**
- BVT 用例是否覆盖了本次变更的端到端核心场景？
- 断言是否精确验证了业务结果（而非仅检查"不报错"）？
- 是否有过度宽松的断言（如 `gte` 代替 `eq`、只检查 status code 不检查 body）导致漏检回归？
- 测试数据是否稳定可控？是否依赖外部状态（特定模型输出、第三方服务）导致 flaky？
- 如果 PR 修复了 bug：是否有专门的回归 BVT 用例能 100% 复现该 bug？

**Eval（效果评估）方案** — 仅当 PR 涉及 LLM/VLM prompt、AI 调用链、模型切换、数据处理管线时审查
- 是否需要 eval 验证？变更是否影响 AI 输出质量（prompt 修改、模型替换、前/后处理逻辑变更）？
- eval 数据集是否充分？是否覆盖了多种输入类型（不同语言、不同格式、边界 case）？
- eval 指标是否明确？是否有量化的通过标准（准确率、召回率、格式合规率等），而非主观判断？
- 回归对比：是否与改动前的 baseline 做了对比？是否有 eval 结果数据支撑"不退化"的结论？
- 如果 PR 未包含 eval 但应该有：指出需要补充 eval 的场景和建议的评估方式

输出格式：
- ✅ 方案合理的部分 + 理由
- 💡 可优化的建议 + 具体方案 + 预期收益
- 🧪 测试方案缺陷/缺失 + 建议补充的测试策略

#### 四、代码审查（逐文件 Review）

对每个变更文件进行审查，关注：
- 代码正确性：逻辑错误、边界条件、空指针、类型安全
- 代码风格：命名规范、函数长度、注释质量
- 错误处理：是否有遗漏的错误处理、错误信息是否清晰
- 可维护性：代码重复、魔法数字、硬编码
- 测试覆盖：关键路径是否有测试

输出格式（按严重程度分类）：
- 🔴 **必须修改**：会导致 bug 或严重问题
- 🟡 **建议修改**：代码质量或可维护性问题
- 🟢 **可选优化**：锦上添花的改进

每条 Review 包含：
```
文件：<file_path>
行号：<line_range>
问题：<description>
建议：<suggestion with code example if applicable>
```

**文档内交叉引用**

报告中经常出现跨章节引用（如"潜在风险"引用"代码审查"中的具体条目）。必须使用 Markdown 锚点链接，使引用可点击跳转：

1. 每条 Review 条目的标题前添加 HTML 锚点 `<a id="issue-N"></a>`（N 为全局编号）：
   ```markdown
   #### <a id="issue-1"></a>1. `pdf_v1.go` — `downloadImageBytes` 无响应体大小限制
   ```

2. 所有引用处使用 Markdown 链接格式 `[🔴 #N](#issue-N)`：
   ```markdown
   - ⚠️ HTTP 图片下载无响应体大小限制（见 [🔴 #1](#issue-1)）
   ```

这样读者在"潜在风险"章节看到引用时，可以直接点击跳转到"代码审查"中的详细描述。

#### 4.5、API / 配置变更清单

当 PR 涉及对外暴露的接口、配置项、数据结构变更时，必须单独列出，帮助调用方和运维快速评估影响。

**检查范围**（有则列，无则整章省略）：

**API 接口变更**
- 新增 / 删除 / 重命名的 HTTP / gRPC / WorkItem 接口
- 请求 / 响应字段的增删改（含类型变更、required 变更）
- 接口行为变更（如返回值语义变化、错误码变化）
- 向后兼容性判断：旧版调用方是否会 break？

**配置项变更**
- 新增 / 删除 / 重命名的配置项（YAML、环境变量、Feature Flag）
- 默认值变更
- 配置项的生效范围（全局 / 租户级 / 请求级）

**数据结构 / Schema 变更**
- 数据库 schema 变更（新增表、字段、索引）
- 消息队列 / 事件 schema 变更
- 文件格式变更（输入 / 输出）

**依赖变更**
- 新增外部依赖（系统命令、第三方服务、SDK）
- 版本升级的 breaking change

输出格式（表格）：

```markdown
| 类型 | 变更项 | 变更内容 | 向后兼容 | 备注 |
|------|--------|----------|----------|------|
| API | `moi:llm.extract.structured` | 合并原 `.advanced`，新增 `json_schema`/`files` 等字段 | ⚠️ 旧 `.advanced` 接口已删除 | 调用方需迁移 |
| 配置 | `extract_config.vl_model` | 新增，默认 `qwen3-vl-plus` | ✅ | 零值回退默认 |
| Schema | `StrikethroughVLMResponse` | 新增 Pydantic model | ✅ | 仅内部使用 |
```

每条变更附带：
- **向后兼容性**：✅ 兼容 / ⚠️ 需迁移 / 🔴 Breaking
- **迁移指引**：如果不兼容，说明调用方需要做什么

#### 五、潜在风险检查

逐项检查以下风险维度：

**并发安全**
- 共享资源是否有竞态条件
- 锁的粒度是否合理
- 是否有死锁风险
- channel/goroutine 是否有泄漏风险

**性能问题**
- 是否有 N+1 查询
- 是否有不必要的内存分配或拷贝
- 循环中是否有可提取的计算
- 数据库查询是否缺少索引
- 是否有可能的慢查询

**复杂度分析**
- 关键函数/算法的时间复杂度是否合理（标注 Big-O）
- 空间复杂度是否可优化（临时数据结构、缓冲区大小）
- 在大数据量场景下是否存在性能退化风险
- 是否有更优复杂度的替代算法

**成本问题**
- 是否有不必要的 API 调用（云服务、第三方）
- 资源是否及时释放（连接、文件句柄）
- 缓存策略是否合理
- 日志级别是否合适（避免生产环境过多 debug 日志）

**安全问题**
- 输入是否有校验
- 是否有 SQL 注入、XSS 等风险
- 敏感信息是否有泄漏风险
- 权限检查是否完整

**除幻（LLM/VLM Prompt 质量）** — 仅当 PR 涉及 LLM/VLM prompt 或 AI 调用链时审查

- **Prompt 覆盖率**：prompt 是否覆盖了所有关键场景和边界条件？
  - 输入变体：不同语言、不同格式、异常输入是否都有指令覆盖
  - 输出约束：是否明确约束了输出格式、禁止项、边界行为
  - 负面示例：是否提供了"不要做什么"的 few-shot negative examples
- **Prompt 稳定性**：对 LLM 输出随机性的容错能力
  - 输出解析是否有清洗/归一化逻辑（去代码块、JSON 包装等）
  - 是否有 fallback 策略应对 LLM 不遵守指令
  - 是否依赖精确格式（脆弱）vs 模糊匹配（健壮）
  - 多步调用中前一步幻觉是否会传播累积
- **可编程程度**：prompt 中有多少逻辑可以用确定性代码替代？
  - 能用正则/规则/代码做的事不要交给 LLM（格式校验、数值计算等）
  - LLM 输出后是否有程序化校验层（列数校验、schema 验证等）
  - prompt 中的硬编码值是否应该参数化

输出格式：
- 🧠 幻觉风险 + 具体 prompt 位置 + 改进建议
- ✅ 已检查无问题的维度

**省 Token（LLM/VLM 调用效率）** — 仅当 PR 涉及 LLM/VLM 调用时审查

- **执行性能**：
  - 串行 vs 并行？是否有可并行化的串行调用？
  - 总耗时与数据规模的关系（如 N 页 = O(N) 延迟）
- **Token 复杂度**（分析 token 消耗与数据规模 N 的关系）：
  - 输入 token：O(1) 固定 prompt vs O(N) 全量数据？
  - 输出 token：期望输出与数据规模的关系
  - 总 token = 调用次数 × 单次消耗（如 N 次 × O(N) = O(N²)）
  - 是否有截断/摘要策略将 O(N) 降为 O(1)
- **总体消耗**：
  - 与改动前相比总 token 增减？
  - 是否有冗余信息重复发送（如每次都发完整上下文）
  - prompt 模板是否可精简？是否可缓存/复用减少调用？

输出格式：
- 💰 Token 效率问题 + 具体位置 + 优化建议 + 预估节省
- ✅ 已检查无问题的维度

**快速迭代（可插拔性与演进能力）** — 评估变更是否有利于后续快速开发

- **可插拔**：核心策略/算法是否以可插拔方式实现？
  - 是否通过策略模式、接口抽象等方式解耦？能否不改主流程就替换实现？
  - LLM/VLM 调用是否有清晰的接口层？切换模型/provider 的成本如何？
  - 新增的处理步骤能否独立启用/禁用？
- **可开关**：关键行为是否支持配置化控制？
  - 新功能是否有 feature flag 或配置项控制启停？
  - 关键参数（截断行数、重试次数、阈值、模型选择等）是否可配置而非硬编码？
  - 是否支持灰度（按租户/文件类型等维度逐步开启）？
- **可替换**：当前实现能否低成本替换为更优方案？
  - 核心逻辑是否职责单一、边界清晰？能否独立演进不影响其他模块？
  - 数据结构和接口设计是否为未来扩展留有余地？
- **可测试**：新增逻辑是否易于单元测试？
  - 是否有难以 mock 的外部依赖耦合？
  - 纯函数 vs 有副作用的方法比例是否合理？
- **可调试**：出问题时能否快速定位？
  - 是否有足够的中间状态日志？prompt 和 LLM 响应是否可追溯？
  - 新旧方案能否方便地 A/B 对比？

输出格式：
- 🔧 迭代障碍 + 具体位置 + 改进建议
- ✅ 已检查无问题的维度

**测试实现质量** — 与"方案评审"中的测试方案梳理互补，此处聚焦代码级实现细节

- 已有测试是否因本次改动需要更新？更新后断言是否仍然有效？
- 测试代码本身是否有 bug（错误的 expected 值、遗漏的 cleanup、资源泄漏）？
- 测试执行是否稳定？是否有 timing、ordering、环境依赖导致的 flaky 风险？

输出格式：
- 🧪 测试实现问题 + 具体位置 + 修复建议
- ✅ 已检查无问题的维度

输出格式（通用风险）：
- ⚠️ 发现的风险 + 具体位置 + 修复建议
- ✅ 已检查无问题的维度

---

### 5. 输出最终报告

将所有维度的审查结果合并为一份完整报告，在终端直接输出。

### 6. 归档审查报告

审查报告输出后，同时将完整报告保存为 Markdown 文件到 `~/pr_review/` 目录备案：
- 文件名格式：`<repo>_PR<number>_<title>_<YYYYMMDD>.md`（例如 `matrixflow_PR8638_paddle-server-optimize_20260318.md`）
- repo 名从 PR URL 中提取（取最后一段，如 `matrixorigin/matrixflow` → `matrixflow`）
- title 从 PR 元数据中获取，去掉特殊字符，空格替换为 `-`，截断到 50 字符以内
- 如果目录不存在则自动创建
- 文件内容为完整的审查报告（与终端输出一致）

**重新 Review 时保留历史报告**：写入新报告前，检查 `~/pr_review/` 下是否已存在同名文件。如果存在，将旧文件重命名为 `_bakNNN` 格式保留（NNN 为三位数序号，从 001 递增），然后再写入新报告。重命名规则：去掉原文件的 `.md` 扩展名，追加 `_bakNNN.md`。如果已有 `_bakNNN.md`，则找到当前最大序号 +1。示例：
```bash
# 首次重新 review：
# matrixflow_PR8638_paddle-server-optimize_20260318.md
# → matrixflow_PR8638_paddle-server-optimize_20260318_bak001.md

# 再次重新 review（已有 _bak001.md）：
# matrixflow_PR8638_paddle-server-optimize_20260318.md
# → matrixflow_PR8638_paddle-server-optimize_20260318_bak002.md
```

### 7. 折叠历史审查评论（Hide Outdated）

发布新报告前，检查 PR 上是否已有当前用户发布的历史审查评论，如果有则通过 GraphQL `minimizeComment` 将其标记为 OUTDATED 折叠。

```bash
# 1. 获取当前用户名
CURRENT_USER=$(gh api user --jq '.login')

# 2. 获取 PR 所有评论的 node ID、作者、是否已折叠、body 前 200 字符
#    使用分页获取全部评论（每次 100 条）
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      comments(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          author { login }
          isMinimized
          body
        }
      }
    }
  }
}' -f owner=<OWNER> -f repo=<REPO> -F pr=<PR_NUMBER>

# 3. 筛选：author.login == CURRENT_USER && !isMinimized && body 包含审查报告特征
#    审查报告特征：body 以 "# Code Review:" 开头，或包含 "## 〇、总结（TL;DR）"
#    对每条匹配的评论执行 minimize：
gh api graphql -f query='
mutation($id: ID!) {
  minimizeComment(input: {subjectId: $id, classifier: OUTDATED}) {
    minimizedComment { isMinimized }
  }
}' -f id=<COMMENT_NODE_ID>
```

注意：
- 只折叠当前用户自己的评论，不影响其他人的评论
- 只折叠未被折叠的评论（`isMinimized: false`）
- 通过 body 内容特征识别审查报告，避免误折叠普通讨论评论
- 如果有多条历史审查评论，全部折叠

### 8. 发布审查报告到 PR Comment

归档完成后，将完整审查报告作为 PR comment 发布：
```bash
gh pr comment <PR_NUMBER> --repo <OWNER/REPO> --body-file <归档的md文件路径>
```

---

## 审查原则

1. **务实导向**：只提有价值的建议，不吹毛求疵
2. **给出方案**：每个问题都附带具体的修复建议或代码示例
3. **分清主次**：严重问题优先，风格问题次之
4. **理解意图**：结合 PR 目的和上下文来评审，避免脱离业务的纯技术挑剔
5. **中文输出**：报告使用中文

## Gotchas

1. **大 PR diff 截断**：先用 `grep -n '^diff --git'` 定位文件边界，再按需 `sed -n` 读取，避免上下文溢出。
2. **自动生成文件**：swagger.json、docs.go 等跳过，仅确认存在。
3. **私有仓库**：`web_fetch` 无法访问私有仓库，必须使用 `gh` CLI。
4. **上下文不足时**：如果 diff 不足以判断问题，用 `gh api` 获取完整文件内容辅助判断。
