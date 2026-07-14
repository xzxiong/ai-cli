# 纯设计模式 — 方案评审 Checklist

Use this mode for design/docs/spec/RFC PRs that do not change runtime behavior. The goal is to decide whether the design can serve as an implementation baseline.

## Report Structure

```
# Design Review: <PR title>

PR 基础信息
## 〇、总结（TL;DR）
## 一、设计目标与边界
## 二、方案一致性与完整性
## 三、契约与模块边界
## 四、存量迁移、灰度与回滚
## 五、实施门禁与验证计划
## 六、阻塞问题与开放问题
```

Do not include "代码审查（逐文件）" or function-level style review sections in this mode.

## PR 基础信息

```markdown
- **PR**: [#<number> <title>](<pr_url>)
- **分支**: `<head>` -> `<base>` | **变更**: +<additions> / -<deletions>，<file_count> 个文件
- **作者**: <author(s)> | **标签**: <labels>（无则省略）
- **模式**: 📐 纯设计 Review
```

## 〇、总结（TL;DR）

- 一句话说明设计要建立的目标状态。
- 设计成熟度：🟢 可作为实现基线 / 🟡 补齐后可作为基线 / 🔴 不应作为实现基线。
- 关键阻塞或缺口摘要，按 🔴 / 🟡 / 🟢 分级。
- 合并建议必须写成"设计基线建议"，避免暗示代码实现已通过。

## 一、设计目标与边界

- 背景、问题、目标用户或调用方是否清晰。
- Non-goals 是否明确，避免实现方把示例当成契约。
- 前提假设是否可验证，是否依赖未说明的外部系统能力。
- 设计适用范围是否覆盖所有相关入口、角色、数据对象和失败路径。

## 二、方案一致性与完整性

- 文档内部是否有术语、状态机、数据流、权限、错误码、生命周期矛盾。
- 是否定义正常流、异常流、边界值、并发/幂等、审计/观测。
- 是否遗漏关键场景：老数据、异步任务、后台作业、SDK/API、UI、临时链接、权限绕过入口。
- 是否明确哪些内容是规范性要求，哪些只是示例。

## 三、契约与模块边界

- 单一事实源是否明确：schema/proto/OpenAPI/config/DB/策略存储谁是源头。
- 模块职责是否清楚，是否把业务事实源放到不该拥有它的共享层或适配层。
- 对外接口、错误码、状态枚举、兼容性、生成链路是否有落点。
- 安全、权限、租户隔离、数据归属、审计责任是否落在正确边界。

## 四、存量迁移、灰度与回滚

- 存量数据、存量用户、旧 API/SDK、历史任务和运行中任务如何处理。
- 是否有分阶段门禁、灰度策略、开关、回滚路径和读写切换规则。
- 是否定义数据迁移、回填、校验、drift/readback、失败重试与人工修复。
- 是否避免长期双事实源、静默 fallback、默认替换或 best-effort 行为。

## 五、实施门禁与验证计划

- 每个阶段是否有可执行的验收标准，而不是只描述方向。
- 是否列出必须先落地的契约文件、迁移脚本、测试、BVT/eval、监控和文档更新。
- 是否能从门禁判断"能不能进入下一阶段"和"能不能对外发布"。
- docs-only PR 不要求代码测试；评审验证计划是否足以约束后续实现。

## 六、阻塞问题与开放问题

Findings use the same severity labels as other modes:

- 🔴 must fix: design contradiction, missing source of truth, unsafe rollout, security/permission hole, or a gap that would make implementation ambiguous or unsafe.
- 🟡 should fix: important missing detail, unverifiable assumption, incomplete migration/test/observability plan.
- 🟢 optional: clarity improvement or useful future implementation guidance.

Each finding must cite document path/line or section, explain downstream implementation impact, and give a concrete document change. Use supporting code evidence only to validate whether the design matches the current repository.

## Design Mode Principles

1. Review the proposal as a contract, not as implementation code.
2. Prefer fewer, sharper findings over exhaustive wording edits.
3. Do not mark "no tests" as a defect for docs-only PRs; judge the proposed validation plan.
4. Do not submit GitHub approval/request-changes by default; the report may still state design-baseline readiness.
