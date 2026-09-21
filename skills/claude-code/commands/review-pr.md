对 PR 进行全面 Code Review，输出结构化审查报告（中文）。

Input: $ARGUMENTS (PR URL 或 #number, 可选: --explore, --ops, --with-issue)

## Review 模式

- **标准模式**（默认）：面向成熟方案，全面审查
- **探索模式**（`--explore`）：面向 Demo/PoC，侧重方案梳理、逻辑自洽、可观测性、可迭代性
- **Ops 模式**（`--ops` 或自动识别）：面向基础设施/部署仓库，侧重资源配置、安全、影响范围、环境一致性

**模式判断**：
1. `--explore` → 探索模式
2. `--ops` → Ops 模式
3. PR 来自 `ops`/`gitops`/`moi-gitops`/`moi-op` 仓库 → Ops 模式（自动识别）
4. 否则 → 标准模式

## 流程

### 1. 获取数据
```bash
gh pr view <number> --json title,body,files,commits,additions,deletions,baseRefName,headRefName,labels,state
gh pr diff <number> 2>&1 | grep -n '^diff --git'  # 文件索引
gh pr diff <number> 2>&1 | sed -n '<START>,<END>p'  # 按需读取
```
跳过 swagger.json、docs.go 等自动生成文件。

### 2. 标准模式报告结构

**PR 基础信息** → **〇、总结(TL;DR)** → **一、PR 描述评审** → **二、变更概述** → **三、方案评审（含测试方案梳理）** → **四、代码审查（逐文件）** → **4.5、API/配置变更清单** → **五、潜在风险检查**

#### 代码审查分级
- 🔴 必须修改（bug/严重问题）
- 🟡 建议修改（质量/可维护性）
- 🟢 可选优化

#### 潜在风险维度
并发安全、性能(N+1/复杂度)、成本(API调用/资源释放)、安全(注入/XSS)、LLM Prompt 质量（幻觉/稳定性/可编程度/模型兼容）、Token 效率、可插拔性、违禁操作（超时硬编码等）、测试实现质量

#### 文档内交叉引用
每条 Review 用 `<a id="issue-N"></a>` 锚点，引用处用 `[🔴 #N](#issue-N)` 链接。

### 3. 探索模式报告结构

**〇、总结** → **一、方案全景梳理**（目标/数据流图/第三方交互/模块拆解） → **二、逻辑自洽性**（描述vs实现/模块间一致性/并发模型） → **三、可观测性**（LLM/VLM 量化指标：质量/效率/稳定性） → **四、可迭代性** → **五、阻塞性问题**（仅 crash/数据丢失/安全泄漏）

### 4. Ops 模式报告结构

**〇、总结**（影响环境/风险等级） → **一、变更影响分析**（影响范围/环境一致性） → **二、资源配置审查**（计算/存储/网络） → **三、安全审查**（Secret管理/权限控制/网络安全） → **四、Pulumi/Helm 代码审查**（Pulumi代码/Helm chart/配置） → **五、运维风险检查**（破坏性变更/部署顺序/监控告警/CI-CD）

**Ops 仓库识别**:
| 仓库 | 技术栈 | 审查侧重 |
|------|--------|---------|
| `ops` | Pulumi (Go+TS) | IDC/AWS 基础设施，资源配置合理性 |
| `gitops` | Pulumi (Go) | ACK 云服务部署，配置一致性 |
| `moi-gitops` | Pulumi (Go) + Helm | IDC moi-core，Helm values/secret |
| `moi-op` | Pulumi (Go) + Helm | IDC 私有化全套，chart/hook |

### 5. 归档
保存到 `~/pr_review/<repo>_PR<number>_<title>_<YYYYMMDD>.md`
已存在则重命名旧文件为 `_bakNNN.md` 保留。

### 6. 折叠历史审查评论
用 GraphQL `minimizeComment(classifier: OUTDATED)` 折叠当前用户之前发布的审查报告。
识别特征：body 以 `# Code Review:` 开头或包含 `## 〇、总结（TL;DR）`。

### 7. 发布
```bash
gh pr comment <number> --repo <OWNER/REPO> --body-file <md文件路径>
```

## 审查原则
1. 务实导向，只提有价值的建议
2. 每个问题附带具体修复建议或代码示例
3. 严重问题优先，风格问题次之
4. 结合 PR 目的和上下文评审
