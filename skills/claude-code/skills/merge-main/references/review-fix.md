# `--review`：合并后本地审查与自动修复

仅由 `merge-main --review` 调用。`--review` 是针对当前分支与本次目标分支的本地审查开关，不是 `review-pr` 的模式参数；除非用户另行指定，使用 `review-pr` 标准模式。Ops 仓库仍按 `review-pr` 的自动识别规则使用 Ops 模式。

## 1. 前置条件与审查基线

- 必须先完成 merge/rebase（含冲突解决和原 Step 6 基础验证），不存在 `MERGE_HEAD`、进行中的 rebase 或未解决冲突。合并失败时停止，不做审查代替合并。
- 基线使用本次 fetch 后的 `<upstream-remote>/<target-branch>`，记为 `BASE_REF`；不要改成 `main`、`origin/main`、PR 当前 base 或另一分支。当前工作分支记为 `HEAD_REF`。
- 先记录 `git status --short` 和 `git diff --stat`；该阶段产生的修复与合并前遗留改动不能混淆。正常流程中 Step 1 已要求工作区干净，gates 可能留下的改动属于既有 gates 修复，不得覆盖或丢弃。
- 使用 merge-base 三点 diff，确保审查包含当前分支相对 base 的全部改动，以及合并后的组合结果；`git diff BASE_REF HEAD` 或直接比较 merge commit 的两个 parent 都不能替代本范围。

```bash
BASE_REF=<upstream-remote>/<target-branch>
BASE_SHA=$(git rev-parse "$BASE_REF")
MERGE_BASE=$(git merge-base "$BASE_SHA" HEAD)
REVIEW_DIFF=$(mktemp --suffix=.diff)
# 单个 commit 与工作区的比较包含已暂存和未暂存改动；也能覆盖此前 gates 修复。
git diff --no-ext-diff "$MERGE_BASE" > "$REVIEW_DIFF"
git diff --name-only "$MERGE_BASE"
git status --short
```

后续 $REVIEW_DIFF 必须替换为临时文件的**绝对路径**，不要原样执行带占位符的命令。审查范围是 `MERGE_BASE` 到最终工作区，不能误换成 `BASE_SHA...HEAD` 而漏掉合并结果。文件仅在当前仓库使用，不含远端 diff；大 diff 先列文件边界再分段读取，生成文件与二进制文件按 `review-pr` 规则处理。未跟踪文件不会出现在普通 `git diff` 中，须根据 `git status` 单独读取；如属于本次修复，纳入审查，否则不要临时 stage 来制造 diff。

## 2. 按 review-pr 执行本地审查

1. 通过 Skill 工具调用 `review-pr`，参数明确写出：

   ```text
   本地 diff 审查：当前分支 <HEAD_REF> 对比 <BASE_REF>（merge-base <MERGE_BASE>）。
   diff 文件：<REVIEW_DIFF 的绝对路径>。当前工作区文件为该 diff 的 new side。使用标准模式（Ops 仓库按自动规则选择 Ops）。
   只执行本地数据获取、设计上下文提取、checklist 审查与报告生成；不要发布、归档到 PR 或提交 GitHub review。
   ```

   不得只使用 Fast checklist 冒充完整审查。若因上下文或工具限制只能静态审查，必须报告降级原因及未验证项目，不能宣称标准审查全部完成。
2. `review-pr` 的 Step 1 改为读取本地 diff 与当前工作区文件；统计与文件索引均来自上述 merge-base。若此前已有 gates 修复，也视为最终工作区的一部分审查，不修改或回退它们来迎合 review。读取必要的上下游调用方、测试和配置，不局限于 diff 行。
3. Step 2 优先使用现有本地 PR 描述、关联 Issue、设计文档和提交信息；本地没有、但存在与当前分支完全对应的 PR 时，可通过 `gh` 只读获取这些上下文。不得因没有 PR、无关联 Issue、无设计文档或 `gh` 不可用而跳过代码审查。找不到设计说明时照常标注，但不把它自动列为代码修复项。
4. Step 3 完整遵守所选模式的模式判断、深度开关和 checklist 加载要求；标准模式必须读取 testing 与 risks，条件命中时读取 architecture / data-access。
5. Step 4 保留完整中文结构化报告与 `I-N` 编号。PR 专属字段可写 `本地分支：<HEAD_REF>`、`Base：<BASE_REF>`；每个 🔴/🟡/🟢 finding 必须有实际证据、文件/行号和修复建议。
6. **跳过 Step 5-8**：本阶段不折叠评论、不 `gh pr comment`、不 `gh pr review`，也不自动 push。即使当前分支已有 PR，也不得把本地结果作为 GitHub review 发布。报告保留在当前会话供逐项修复；用户另行要求归档时可保存到非仓库文件，但不伪装成已发布的 PR 报告。
7. 报告中的「合并建议」只表示审查时的代码状态，不触发远端决议；修复完成后需以复审结果更新，不沿用初轮结论。

## 3. 自动修复范围与执行纪律

- 🔴 **必须修改** 与 🟡 **建议修改**：逐条确认后自动修复；范围包括代码、测试、风险及方案章节中有证据支持的具体问题，不限于「四、代码审查」。🟢 可选优化默认不处理。
- 修复前先复核 finding 与当前代码：误报、已被后续代码解决、纯 PR 描述/设计文档缺失、需产品决策或超出本次改动所有权的事项不能乱改。逐项记录 `FIXED` / `REJECTED（误报）` / `BLOCKED（原因）`，不能静默删除 finding 来制造全绿。
- 🔴 不得以「建议类」为由跳过；🟡 仅在客观阻塞或修复会引入不相称的新风险时保留，必须说明权衡和剩余影响。产品需求、兼容性破坏或跨团队变更存在歧义时，先询问用户，不擅自扩大方案。
- 优先 🔴 后 🟡；同一文件的关联问题一起处理，避免相互覆盖。遵循仓库约定，保持最小、可验证的修改；不通过删除测试、弱化断言、跳过检查、放宽权限、缩减正常功能或调整阈值修绿。
- 涉及公共接口、调用链、数据访问、并发或错误处理时，追踪必要的上下游代码。修复应为可复现问题补充或调整测试；纯文档/PR 描述建议不改业务代码。
- 自动修复只限工作区编辑和本地验证。**不自动 commit、amend、rebase、push**，也不改写已完成的 merge 或 rebase 历史；用户另行授权提交时才提交。
- 与 `--gates` 组合时，gates 修复和 review 修复都保持未提交；不得用 review 修复掩盖失败 gates，也不得丢弃 gates 阶段已有修改。

## 4. 验证与复审闭环

1. 每组修复先运行定向测试/静态检查，再运行受影响的回归。标准审查因测试缺失提出的问题，需要补测试并实际执行；只有实际成功退出的项目记为 `PASS`。
2. `--review --gates` 的顺序：原 Step 7 → gates 回归与修复 → review/fix → 定向复跑 → 所选 gates 最终复跑 → review 复审。基础验证、gates 与 review 所需检查重叠时可复用针对同一最终代码的成功结果，不机械重复，但不能因此省略 gates 最终全量回归。
3. 所有可处理的 🔴/🟡 修复完成后，对**最终工作区**再次按同一 merge-base 范围做本地复审。通过 Skill 工具再次调用 `review-pr`，沿用本地模式，使用刷新后的同一临时 diff 文件：

   ```bash
   # 直接用 merge-base 对比工作区，已包含 staged + unstaged；不要 HEAD 与工作区多段拼接。
   git diff --no-ext-diff "$MERGE_BASE" > "$REVIEW_DIFF"
   ```

   保留原始报告中的 `I-N` 作为修复追踪键；复审发现的新问题续编号，不复用旧编号。审查最终组合代码，不分别孤立审查 merge commit 和修复。每轮重新检查 `git status`，把属于本次修复的未跟踪文件单独提供给审查；不要为了纳入 diff 而擅自 stage。更新临时 diff 后必须发起新的复审，不能把前一轮报告当作最终结果。
4. 复审仍发现可处理的 🔴/🟡 时继续修复、定向验证、再复审，直到仅剩有依据的 `REJECTED` / `BLOCKED`；不得设置低次数上限后宣称完成。若连续修改引入同类回归或需求阻塞，停止循环并报告。
5. 最终再次确认没有未解决冲突、无关文件或意外生成物；保留全部修复在工作区供用户检查。不要自动推送或发布 PR 评论。

## 5. 最终报告

在原合并报告中追加：

```text
🔍 Review: <标准 / Ops> | Base: <BASE_REF>@<sha> | merge-base: <sha>
📋 Findings: 🔴 N（FIXED n / REJECTED n / BLOCKED n） | 🟡 N（同上） | 🟢 N（未自动处理）
🛠️ Review fixes: <files / 无> | Commits: 未创建
✅ Verification: <实际执行的检查与结果>
🔁 Final review: CLEAN / <剩余 finding 与原因>
🚪 Gates（若启用）: <最终结果；未启用则省略>
```

`CLEAN` 仅表示最终本地审查没有未处理的 🔴/🟡，不表示 CI 已通过或代码已提交。初轮审查被降级、验证未执行或存在 `BLOCKED` 时必须明确列出，不能写「全部通过」。
