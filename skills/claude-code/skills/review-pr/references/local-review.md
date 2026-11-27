# 本地 Diff 审查

仅在输入含 `--local` 或 `--diff` 时使用。本地是**数据来源模式**，与标准 / Fast / 探索 / Ops 审查模式正交；除本文件明确替换的数据获取、上下文和发布步骤外，完整遵守主 skill 与所选 checklist。

## 1. 输入与边界

```text
/review-pr --local [base-ref] [--fast | --explore | --ops]
/review-pr --diff <path> [--fast | --explore | --ops]
```

- `--local` 不带 base-ref：审查 `HEAD` 到当前工作区的全部改动，包括 staged、unstaged 和未跟踪文件。
- `--local <base-ref>`：先求 `merge-base(base-ref, HEAD)`，再审查该 merge-base 到当前工作区的全部改动。这样包含当前分支已有提交、merge/rebase 结果和后续未提交修复，不会把 base 自身新增提交误算为变更。
- `--diff <path>`：直接审查用户提供的 Git unified diff；path 必须是实际文件路径。不能同时传 `--local` 或 PR URL / `#number`。当前目录是对应仓库时读取工作区补充上下文，否则以 diff 为事实范围，并注明无法获得的周边代码。
- PR 模式与本地模式互斥。缺少 `--diff` 值、base ref 无法解析、merge-base 不存在、当前目录不是所需 Git 仓库时，停止并说明；不能静默退回两点 diff、当前 `HEAD` 或某个默认分支。
- 本地模式不 fetch、不 checkout、不 stage、不 commit、不 rebase、不修复产品代码。自动修复由调用方（如 `merge-main --review`）另行执行。
- 默认不需要 `gh`、PR、Issue 或网络。没有 PR / Issue / 设计文档不是跳过审查的理由，也不是自动产生的代码 finding。
- **Step 6-8 全部跳过**：不折叠评论、不 `gh pr comment`、不 `gh pr review`、不 push。即使发现与当前分支同名的 PR，也不能把本地工作区审查结果发布到该 PR。需要 GitHub 决议时使用 PR 模式，审查已推送的 head。
- Step 5 默认不生成持久归档，只在当前会话输出完整报告。用户明确要求本地归档时，保存为 `~/pr_review/<repo>_LOCAL_<branch-or-diff-name>_<YYYYMMDD>.md`，备份规则与 PR 模式相同；归档不代表已发布。

## 2. `--local`：确定固定基线与工作区范围

在仓库根目录执行。若用户提供 base-ref，将其赋给 `BASE_REF`；不带 base-ref 时使用 `HEAD`。解析后将 SHA 和 merge-base 记录到报告，审查期间不要用会移动的分支名替代固定 SHA。

```bash
BASE_REF=<用户提供的 base-ref；未提供时为 HEAD>
BASE_SHA=$(git rev-parse --verify "$BASE_REF^{commit}")
HEAD_SHA=$(git rev-parse --verify HEAD)
MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")
REVIEW_DIFF=$(mktemp "${TMPDIR:-/tmp}/review-pr-local.XXXXXX")

# 单个 commit 与工作区比较，天然包含 staged + unstaged。
git diff --no-ext-diff --binary "$MERGE_BASE" -- > "$REVIEW_DIFF"
git diff --stat "$MERGE_BASE" --
git status --short
```

`mktemp` 的实际绝对路径替换后续 `$REVIEW_DIFF`。不带 base-ref 时 `BASE_SHA == HEAD_SHA == MERGE_BASE`，这正是仅审查工作区改动，不是无意义比较。

### 未跟踪文件

普通 `git diff` 不包含未跟踪文件。使用 `git ls-files --others --exclude-standard -z` 枚举非 ignored 文件，并将文本文件作为 new-file diff 追加到同一个临时 diff：

```bash
while IFS= read -r -d '' path; do
  rc=0
  git diff --no-index --no-ext-diff --binary -- /dev/null "$path" >> "$REVIEW_DIFF" || rc=$?
  if [ "$rc" -gt 1 ]; then
    printf 'Failed to read untracked file: %s\n' "$path" >&2
    exit "$rc"
  fi
done < <(git ls-files --others --exclude-standard -z)
```

`git diff --no-index` 发现差异返回 1，这是预期结果；大于 1 才是读取错误。不能为了生成 diff 而 `git add`。未跟踪文件也要纳入文件索引；二进制和大生成文件按 Gotchas 跳过内容，但需在范围说明中列出。ignored 文件不属于默认审查范围。

### 一致性检查

- 报告记录 `BASE_REF@BASE_SHA`、`HEAD_SHA`、`MERGE_BASE`、工作区状态及临时 diff 路径。
- 如果调用方传入预期 base / merge-base，实际计算结果必须一致；不一致时停止并请调用方确认基线，不能继续用过期上下文审查。
- 开始报告前检查 `HEAD`、index 和工作区是否发生变化。若发生变化，重新生成完整 diff 和文件索引，确保 finding 对应同一份最终代码；不能把不同轮次的 diff 拼接后当作一个快照。
- 没有跟踪文件差异且没有非 ignored 未跟踪文件时，明确报告“本地无待审查差异”，不要凭空生成问题。

## 3. `--diff`：使用显式 diff

1. 将 path 转为绝对路径，确认文件可读且非空。文件是本次审查的唯一 diff 事实源，不再混入当前工作区的其他修改。
2. 使用 `grep -n '^diff --git'` 建立文件索引，再按段读取；读取文件头中的 old/new path、new-file/deleted-file、rename 和 binary 标记。只有 hunk、缺少完整文件头的输入要明确标注为不完整 diff。
3. 当前仓库文件与 diff new side 对应时，可读取完整文件和调用方。发现工作区与 diff 不一致时，以 diff 为准并注明，不得把无关工作区代码当作该变更的问题。
4. 未提供 base/head 元数据时，报告使用 diff 文件名和文件索引，不伪造分支、commit、PR 或测试状态。

## 4. 替换主流程中的数据与设计上下文

### Step 1：本地数据获取

- 用上述本地 diff 代替 `gh pr view` / `gh pr diff`。 additions、deletions、文件数、重命名、生成文件和源码文件数均从该 diff 统计。
- 读取优先级不变：业务逻辑 > schema/model > 配置 > 测试 > 文档。必须读取必要的完整文件、调用方、mock、测试、配置和 CI 适配，不能只评论孤立 hunk。
- 行号优先引用 new side 对应的当前文件行；显式 diff 无对应文件时引用 diff 中的 new line，并说明来源。
- 深度开关根据本地 diff 统计、分支名、commit message 和本地设计文档判断；没有 PR 标题/描述不影响其他触发条件。

### Step 2：本地设计上下文

仍须寻找设计意图，但来源改为：

1. 用户在调用参数中提供的背景、验收标准、Issue/设计文档路径。
2. 仓库内与变更匹配的 `docs/`、`spec/`、`design/`、ADR、README 和当前模块规则。
3. 当前分支相对 base 的 commit message；没有 base 时仅参考当前工作区关联说明，不拿无关历史猜测需求。
4. 用户明确给出的 Issue/PR 编号或 URL 可作为只读补充上下文；即使读取，也仍遵守本地模式禁止发布的边界。`--with-issue` 只影响上下文获取，不授权评论或 review。

找不到设计说明时，在本地报告的「变更意图与设计上下文」标注“未找到，以下基于代码与提交信息推断”，继续审查。不要输出“PR body 缺失”作为本地代码问题，也不要因无 PR 给 Goal-Result 对齐直接判 🔴。

### Step 3-4：沿用模式与报告骨架

- 标准 / Fast / 探索 / Ops 的选择、互斥关系、checklist 加载、深度开关、证据要求和 `I-N` 分级全部保持不变。
- 报告标题改为 `# Code Review (Local Diff): <branch-or-diff-name>`；Fast 模式为 `# Fast Review (Local Diff): <branch-or-diff-name>`。
- 「PR 基础信息」改为「审查基础信息」，列出本地分支 / diff 文件、base@SHA（若有）、head SHA（若有）、merge-base（若有）、工作区状态、变更统计和审查模式。
- 「一、PR 描述评审」改为「一、变更意图与设计上下文」，按上述本地来源说明目标、方案与验收依据。其余方案、Goal-Result、测试、代码、SQL、风险章节照常执行。
- TL;DR 保留 🔴/🟡/🟢 数量与「建议合并 / 修复后合并 / 需要重大修改」，但明确这是**本地合并建议，不触发 GitHub review**。Fast 模式仍须写明“基于静态审查，测试未执行”。
- 测试与 CI 只报告实际执行结果；未执行、环境阻塞、仅有测试代码均不能写成 PASS。本地 CLEAN / 建议合并不代表远端 CI 通过或代码已提交。

## 5. 本地审查输出

完整结构化报告之后附上：

```text
Local review: <base...workspace / explicit diff>
Base / merge-base: <refs + SHA / unavailable>
Workspace: <clean / staged + unstaged + untracked summary / not applicable>
Publication: SKIPPED (local mode)
Archive: <path / SKIPPED>
Code changes by review: NONE
```

finding 必须能被后续自动修复流程逐项引用。审查自身不将 finding 标记为 FIXED，也不编辑代码；后续修复和复审由调用方负责。
