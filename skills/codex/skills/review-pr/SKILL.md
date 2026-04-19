---
name: review-pr
description: 严格版 GitHub PR 审查：证据驱动、阻断条件明确、结构化中文报告、自动归档与发布。
metadata:
  short-description: 严格门禁的 PR 审查与自动发布
---

# Review PR (Strict)

用于高标准 PR 审查。要求证据充分、结论可追溯、合并建议有明确门禁。

## 何时使用

- `review pr <url|#number>`
- `代码审查` + PR 链接/编号
- 需要“严格评审 / 阻断条件 / 可直接发评论”

## 强制规则（MUST）

- 必须基于实际 diff 与上下文给结论，不允许猜测。
- 每条问题必须包含：`文件`、`行号`、`风险`、`修复建议`。
- 结论必须分级：🔴 阻断合并 / 🟡 建议修改 / 🟢 可选优化。
- 发现高风险但证据不足时，必须标注“需补充信息”，不能直接判定通过。
- 未覆盖的关键检查项必须在报告中显式写“未验证 + 原因”。

## 执行流程

1. 获取 PR 元数据
- `gh pr view <PR_NUMBER> --repo <OWNER/REPO> --json number,title,body,author,files,commits,additions,deletions,baseRefName,headRefName,labels,state,url`

2. 获取并分段阅读 diff
- `gh pr diff <PR_NUMBER> --repo <OWNER/REPO> | grep -n '^diff --git'`
- 按关键文件分段读取；优先 `handler/service/repo/model/test`
- 跳过生成文件（`swagger.json`、`docs.go` 等），但需在报告中注明已跳过

3. 可选关联 Issue（仅用户要求）
- `gh issue view <ISSUE_NUMBER> --repo <OWNER/REPO> --json title,body`
- `gh api repos/<OWNER>/<REPO>/issues/<ISSUE_NUMBER>/comments --jq '.[].body'`

4. 输出严格审查报告（中文）
- 顺序固定：
  - PR 基础信息
  - TL;DR（问题计数 + 合并结论）
  - PR 描述质量（背景/原因/方案/结果）
  - 变更概述
  - 方案评审（UT/BVT/Eval）
  - 逐文件审查
  - API/配置/Schema 变更清单（如有）
  - 风险总表与阻断项

5. 归档
- `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`
- 同名先备份为 `_bakNNN.md` 再写入

6. 折叠历史审查评论（当前用户）
- 仅折叠：当前登录用户（`viewer.login`）+ 未折叠 + 内容匹配审查报告特征
- 覆盖两类评论：`pullRequest.comments`（普通评论）+ `reviewThreads.comments`（行内 review comments）
- GraphQL `minimizeComment` with `OUTDATED`
- 折叠后必须二次校验剩余匹配评论数；若非 0，报告中注明“折叠未完全成功 + 剩余数量”
- 严禁折叠其他用户评论（即使内容匹配）
- 其他用户评论若匹配审查特征，可在新报告中引用其评论链接与要点摘要，但不得执行折叠

7. 发布评论
- `gh pr comment <PR_NUMBER> --repo <OWNER/REPO> --body-file <REPORT_PATH>`

## 严格检查清单（必须逐项判定）

- 正确性：边界条件、空值、错误路径、状态机转换
- 兼容性：API 字段/语义变化、配置默认值变化、迁移成本
- 并发安全：竞态、死锁、goroutine/channel 泄漏
- 性能：N+1、热点循环、无界内存增长、慢查询风险
- 安全：输入校验、注入风险、权限绕过、敏感信息泄露
- 可维护性：重复逻辑、过度耦合、不可测试设计
- 测试充分性：是否覆盖 happy/error/boundary/regression
- LLM 相关（如适用）：幻觉风险、输出约束、token 成本

## 阻断合并规则（Gate）

满足任一条件即“🔴 不建议合并”：
- 存在可复现功能错误或明确回归风险
- 存在 breaking change 且无迁移方案
- 存在高危安全问题（注入、鉴权缺失、数据泄露）
- 关键路径缺少必要测试且无法证明风险可接受
- 关键结论依赖未提供证据（日志、用例、代码上下文）

## 输出格式（强约束）

- 每条问题模板：
  - `文件: <path>`
  - `行号: <line>`
  - `级别: 🔴/🟡/🟢`
  - `问题: <具体风险>`
  - `证据: <diff/逻辑依据>`
  - `建议: <可执行修复>`
- 交叉引用：
  - 问题项：`<a id="issue-N"></a>`
  - 引用处：`[🔴 #N](#issue-N)`

## 合并结论模板（必须二选一）

- `结论：🔴 不建议合并（需修复后复审）`
- `结论：✅ 可合并（仅存在非阻断建议）`

## 注意事项

- 大 PR 必须分段读取，禁止一次性吞全部 diff。
- 上下文不足时先补充取数，再给结论。
- 私有仓库必须优先 `gh` CLI。
