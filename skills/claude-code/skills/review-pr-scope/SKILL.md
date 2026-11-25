---
name: review-pr-scope
description: |
  对 PR 做「缩小实现方案」专项审查：从关联 Issue 与 PR 抽出核心目标与关键成果，
  再据此收敛 diff——允许丰富测试，但反对过分设计、等效冗余、过度封装、
  多余加解密/混淆、过度防御式编程，以及非必要幂等。

  Use this skill whenever the user wants to shrink / scope / slim a PR implementation,
  even if they do not say the skill name. Triggers include:
  - `/review-pr-scope <PR>`、`review-pr-scope #123`
  - 「缩小实现」「收敛方案」「砍过度设计」「去掉冗余封装」
  - 「这个 PR 是不是做多了」「对照 issue 看哪些不该进」
  - 「去幂等 / 去过度防御 / 去掉多余加密」结合 PR 审查
  Prefer this over generic review-pr when the ask is scope/minimalism rather than
  full correctness/security/perf review. Can run after review-pr as a second pass.
---

# Review PR Scope（缩小实现方案）

专项审查：先钉死「要交付什么」，再问「这些改动是否都服务于它」。默认产出中文报告 +
建议删改清单；**默认不发 PR 评论**（加 `--comment` 才发布）。

本 skill 不是完整 Code Review 的替代。正确性/安全/性能仍可用 `review-pr`；这里只回答：
实现是否相对 Issue/PR 目标偏胖。

## 输入

`$ARGUMENTS`：PR URL 或 `#number` / `number`，可选：

| Flag | 作用 |
|------|------|
| `--comment` | 归档后 `gh pr comment` 发到 PR；默认不发 |
| `--with-issue N` | 强制关联 Issue `#N`（覆盖自动提取） |
| `--repo OWNER/REPO` | 当前目录不是该仓库时显式指定 |

不要与 `review-pr` 的 `--fast/--explore/--ops` 混用；用户若只要完整审查，改走 `review-pr`。

## 为什么要这样做

很多 PR 在修一个明确 bug / 交一个明确能力时，顺手加入：

- 对称封装、通用框架、策略表
- 「以防万一」的幂等、重试、去重表
- 多余加解密、签名、混淆
- 双写校验、深层 copy、重复守卫

这些会抬高阅读与回归成本，却不一定推进 Issue 的关键成果。审查时先重建目标，再按目标裁剪，
比按文件逐条挑刺更稳。

## 执行流程

### Step 0. 解析参数

从 `$ARGUMENTS` 解析 PR 编号、repo、是否 `--comment`、是否 `--with-issue`。
repo 优先用 `--repo`，否则从 PR URL 或 `gh repo view --json nameWithOwner` 推断。

### Step 1. 拉取 PR 与关联 Issue

```bash
gh pr view <number> --repo <OWNER/REPO> \
  --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state,author,url

gh pr diff <number> --repo <OWNER/REPO> 2>&1 | grep -n '^diff --git'
# 再按需 sed -n 分段读 diff；跳过 swagger.json / docs.go / generated / 二进制
```

关联 Issue（按优先级）：

1. `--with-issue N`
2. PR body / 标题中的 `Fixes #N` / `Closes #N` / `#N` / issue URL
3. 关键 commit message 中的 issue 引用
4. 仍无 → 在报告标注 `⚠️ 未关联 Issue`，**仅用 PR 标题+body+diff 反推目标**，并降低「越界」判定的强硬程度

```bash
gh issue view <N> --repo <OWNER/REPO> --json title,body,labels,state
# 必要时读 issue comments 里作者/维护者的范围澄清
```

### Step 2. 钉核心目标（Core Goals）

用 Issue + PR 合成 **1～3 条**核心目标。每条写成可判定的交付意图，而不是实现手段。

好的目标：

- 「INSERT/UPDATE 时拒绝非法 geometry subtype，错误信息可读」
- 「TransferPage 写路径在 IO fault 下有界重试，避免 DN OOM」

差的目标（手段冒充目标）：

- 「引入 GeometryValidator 框架并支持插件化」
- 「为所有写路径统一幂等中间件」

规则：

- 目标来自 Issue 验收口径 / 复现条件 / PR 描述的「解决什么」；忽略作者顺带提到的「以后可能」
- 若 Issue 与 PR 冲突：以 Issue 验收为准，把 PR 多做的部分标成范围膨胀候选
- 输出到报告「一、核心目标」；后续所有删改建议必须能指回某一条目标或「无目标支撑」

### Step 3. 钉关键成果（Key Outcomes）

把每条核心目标落成 **可观察成果**（行为、API、错误、指标、数据约束）。通常每目标 1～4 条。

成果回答「合并后 externally 能看见什么变了」，例如：

- 非法 subtype → bind 阶段报错，不再进存储
- 重试次数 ≤ N，失败可观测
- 新增/改动的测试能锁住上述行为

**明确划出 Non-goals**（本 PR 不需要完成的）：泛化框架、无关模块清理、非要求的幂等、非要求的加密、完美抽象。

允许且鼓励：**丰富测试 case**（单元/BVT/回归）只要直接锁关键成果；测试多 ≠ 过度设计。

### Step 4. 对照 diff 做收敛审查

按文件优先级读 diff：业务逻辑 > schema/model > 配置 > 测试 > 文档。对每个实质性变更问：

1. **服务哪条关键成果？** 答不上来 → 范围膨胀候选
2. **是否最小充分？** 能用局部改动却引入框架/间接层 → 过度设计候选
3. **测试是否在锁成果？** 锁成果 → 保留；只测内部封装形状 → 可建议改成行为测试

专项裁剪清单（命中则写入删改建议，附文件/行证据）：

| 类别 | 审查问题 | 典型处理 |
|------|----------|----------|
| 等效冗余 | 新旧路径并存且行为等价？重复校验/转换？ | 删重复路径或合并为一条 |
| 过度封装 | 单实现却抽 interface/工厂/策略表？一层 wrapper 无第二实现？ | 内联；去掉无收益抽象 |
| 多余加解密/混淆 | Issue 未要求保密/防篡改，却新增 encrypt/sign/obfuscate/密钥流转？ | 删除或移出本 PR |
| 过度防御 | 双写核对、处处 deep copy、重复 nil/边界守卫、吞错后「兜底成功」？ | 保留边界处一次校验；去掉叠床架屋 |
| 非必要幂等 | 无重复提交/至少一次投递等需求，却加 dedupe 表、幂等键、无条件可重入包装？ | 删除；若调用方已保证 once，不必再包一层 |
| 过分设计 | 配置开关矩阵、未来扩展点、通用 pipeline，而目标是单点修复？ | 收敛到直达成果的写法 |

**不要**为了「干净」建议删除：

- 直接锁关键成果的测试（即使很多）
- Issue 明确要求的兼容层 / 开关 / 幂等 / 加密
- 与周边代码风格一致的小函数抽取（非单次调用的无意义 wrapper 才打）

严重级别：

- 🔴 必须收敛：明显越出关键成果，或引入非必要幂等/加密/重框架且增加正确性风险
- 🟡 建议收敛：可维护性变差，但短期可接受
- 🟢 可选：品味层面的更短写法

### Step 5. 写报告并归档

按 `references/scope-checklist.md` 模板输出。编号用 `I-N`（不要用 `#N`，避免 GitHub 自动链到 issue）。

归档路径：

```text
~/pr_review/<repo>_PR<number>_scope_<short-title>_<YYYYMMDD>.md
```

若文件已存在，将旧文件重命名为 `_bakNNN.md`（NNN 自 001 递增）再写入。

### Step 6. 可选发评

仅当用户给了 `--comment`：

```bash
gh pr comment <number> --repo <OWNER/REPO> --body-file <归档路径>
```

**默认不做** `gh pr review --approve / --request-changes`。本 skill 产出的是范围意见；合并决议留给 `review-pr` 或人类。若用户明确要求带决议，再按他们的指示执行。

## 报告必须具备的删改清单

「四、建议删改清单」每行尽量可执行：

```markdown
| ID | 级别 | 位置 | 建议动作 | 关联目标/成果 | 理由 |
|----|------|------|----------|---------------|------|
| I-1 | 🔴 | path.go:L120-180 | 删除 IdempotencyMiddleware 及表迁移 | 无成果支撑 | Issue 只要求单次写失败可观测，未要求幂等键 |
```

清单末尾给一个 **Keep 摘要**：哪些大块改动应保留（含测试），避免作者误删成果路径。

## 审查原则

1. **目标先于品味**：没有目标锚点就不标「过度」
2. **测试友好**：丰富行为测试是加分项；反对的是测实现细节的过度夹具/测试专用框架
3. **给出走法**：每条 🔴/🟡 附「删什么 / 改成什么 / 为何仍满足成果」
4. **中文输出**；证据带文件与行号
5. **务实**：小 PR 单点修复不要写成架构论文；大 PR 先按成果分组再裁

## Gotchas

1. 大 diff 先 `grep -n '^diff --git'` 再分段读，避免 context 爆掉
2. 私有仓只用 `gh`，不要用 web_fetch 碰私有内容
3. 无 Issue 时把「核心目标」置信度写低，并把 🔴 更多留给「纯冗余/明显死代码」，少用「作者不该做扩展」式主观 🔴
4. 不要把「与 review-pr 重复的通用 bug 清单」当作本 skill 主产出；发现严重 bug 可附带一笔，但主线仍是范围收敛
5. `--comment` 未给及时，不要发评；在对用户回复里贴报告路径与 TL;DR 即可
