对 PR 进行全面 Code Review，输出结构化审查报告（中文）。

Input: $ARGUMENTS (PR URL 或 #number, 可选: --fast, --explore, --ops, --with-issue)

## Review 模式

- **标准模式**（默认）：面向成熟方案，全面审查
- **Fast 模式**（`--fast`）：高信号静态审查；不跑测试/CI，快速给出可证实问题
- **探索模式**（`--explore`）：面向 Demo/PoC，侧重方案梳理、逻辑自洽、可观测性、可迭代性
- **Ops 模式**（`--ops` 或自动识别）：面向基础设施/部署仓库，侧重资源配置、安全、影响范围、环境一致性

**模式判断**：
1. `--fast` → Fast 模式（显式优先）
2. `--explore` → 探索模式
3. `--ops` → Ops 模式
4. PR 来自 `ops`/`gitops`/`moi-gitops`/`moi-op`/`ob-ops` 仓库 → Ops 模式（自动识别）
5. 否则 → 标准模式

不要组合 `--fast` 与 `--explore` / `--ops`；冲突时先请用户选一种模式。

## 流程

### 1. 获取数据
```bash
gh pr view <number> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state,author
gh pr diff <number> 2>&1 | grep -n '^diff --git'  # 文件索引
gh pr diff <number> 2>&1 | sed -n '<START>,<END>p'  # 按需读取
```
跳过 swagger.json、docs.go 等自动生成文件。

### 2. 读取对应 checklist

完整流程以 skill 为准：`~/.claude/skills/review-pr/SKILL.md`

- Fast → `references/fast-checklist.md`（不跑测试/CI，不读 section-testing）
- 标准 → `references/standard-checklist.md` + `section-testing.md` + `section-risks.md`（条件触发 architecture）
- 探索 → `references/explore-checklist.md`
- Ops → `references/ops-checklist.md`

### 3. 标准模式报告结构

**PR 基础信息** → **〇、总结(TL;DR)** → **一、PR 描述评审** → **二、变更概述** → **三、方案评审（含测试方案梳理）** → **四、代码审查（逐文件）** → **4.5、API/配置变更清单** → **五、潜在风险检查**

#### 代码审查分级
- 🔴 必须修改（bug/严重问题）
- 🟡 建议修改（质量/可维护性）
- 🟢 可选优化

#### 潜在风险维度
并发安全、性能(N+1/复杂度)、成本(API调用/资源释放)、安全(注入/XSS)、LLM Prompt 质量（幻觉/稳定性/可编程度/模型兼容）、Token 效率、可插拔性、违禁操作（超时硬编码等）、测试实现质量

#### 文档内交叉引用
每条 Review 用 `<a id="issue-N"></a>` 锚点，引用处用 `[🔴 I-N](#issue-N)` 链接（不要用 `#N`，避免 GitHub 误链 issue）。

### 4. Fast 模式报告结构

**PR 基础信息**（模式=⚡ Fast Review，测试=未执行） → **〇、总结** → **一、关键发现** → **二、审查边界**

- 不运行测试、不触发/重试 CI、不等待测试结果
- 合并建议若为「建议合并」，必须注明“基于静态审查，测试未执行”

### 5. 探索模式报告结构

**〇、总结** → **一、方案全景梳理**（目标/数据流图/第三方交互/模块拆解） → **二、逻辑自洽性**（描述vs实现/模块间一致性/并发模型） → **三、可观测性**（LLM/VLM 量化指标：质量/效率/稳定性） → **四、可迭代性** → **五、阻塞性问题**（仅 crash/数据丢失/安全泄漏）

### 6. Ops 模式报告结构

**〇、总结**（影响环境/风险等级） → **一、变更影响分析**（影响范围/环境一致性） → **二、资源配置审查**（计算/存储/网络） → **三、安全审查**（Secret管理/权限控制/网络安全） → **四、Pulumi/Helm 代码审查**（Pulumi代码/Helm chart/配置） → **五、运维风险检查**（破坏性变更/部署顺序/监控告警/CI-CD）

**Ops 仓库识别**:
| 仓库 | 技术栈 | 审查侧重 |
|------|--------|---------|
| `ops` | Pulumi (Go+TS) | IDC/AWS 基础设施，资源配置合理性 |
| `gitops` | Pulumi (Go) | ACK 云服务部署，配置一致性 |
| `moi-gitops` | Pulumi (Go) + Helm | IDC moi-core，Helm values/secret |
| `moi-op` | Pulumi (Go) + Helm | IDC 私有化全套，chart/hook |
| `ob-ops` | Ops | 按 Ops 模式审查 |

### 7. 归档
保存到 `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`
已存在则重命名旧文件为 `_bakNNN.md` 保留。

### 8. 折叠历史审查评论
用 GraphQL `minimizeComment(classifier: OUTDATED)` 折叠当前用户之前发布的审查报告。
识别特征：body 以 `# Code Review:` / `# Fast Review:` 开头，或包含 `## 〇、总结（TL;DR）`。

### 9. 发布
```bash
gh pr comment <number> --repo <OWNER/REPO> --body-file <md文件路径>
```

### 10. 按合并建议提交 Review 决议
详见 skill Step 8。Fast 模式 approve 时短评须写“测试未执行”。

## 审查原则
1. 务实导向，只提有价值的建议
2. 每个问题附带具体修复建议或代码示例
3. 严重问题优先，风格问题次之
4. 结合 PR 目的和上下文评审
5. Fast 模式只报可证实的高信号问题，并明确审查边界
