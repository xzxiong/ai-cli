---
name: review-issue
description: |
  对 GitHub Issue 中的技术方案进行深度评审：结合 monorepo 现有代码，分析方案的可行性、优劣势、潜在风险和改进建议。

  Use this skill when:
  - The user says "review issue" followed by an issue URL or number
  - The user invokes `/review-issue <ISSUE_URL>`
  - The user says "分析方案" or "方案评审" with an issue URL or number

  **Agent**: The main agent fetches issue data and relevant code, then generates the analysis report.
---

# Review Issue Skill

## 目的
对 Issue 中提出的技术方案，结合 monorepo 现有代码进行深度评审，输出结构化的方案分析报告。

## 使用方法
```bash
kiro chat "review issue https://github.com/matrixorigin/matrixflow/issues/<ISSUE_NUMBER>"
# 或
kiro chat "review issue #<ISSUE_NUMBER>"
```

## Skill 逻辑

### 1. 获取 Issue 元数据
```bash
gh issue view <ISSUE_NUMBER> --repo <OWNER/REPO> --json title,body,labels,state,assignees,comments
```

### 2. 获取 Issue 评论（补充方案细节）
```bash
gh api repos/<OWNER>/<REPO>/issues/<ISSUE_NUMBER>/comments --jq '.[].body'
```

评论中可能包含方案讨论、补充设计、反对意见等关键信息，需一并纳入分析。

### 3. 提取方案关键信息

从 Issue body + comments 中提取：
- **问题描述**：要解决什么问题？现状是什么？
- **提议方案**：具体的技术方案是什么？
- **涉及模块**：方案会改动哪些模块/文件？
- **关键设计决策**：方案中的核心技术选型和设计取舍

### 4. 定位 monorepo 相关代码

根据方案涉及的模块，在 monorepo 中定位相关代码：
```bash
# 克隆或进入 monorepo（如果本地已有）
# 搜索方案涉及的关键类/函数/模块
gh api repos/<OWNER>/<REPO>/contents/<PATH> --jq '.content' | base64 -d

# 或使用本地代码（如果在 monorepo 目录下）
find . -name "*.py" -o -name "*.go" | xargs grep -l "<关键词>"
```

策略：
- 从 Issue 中提取关键模块名、类名、函数名
- 搜索 monorepo 中对应的现有实现
- 重点关注方案要修改/扩展的代码区域
- 理解现有架构约束和依赖关系

### 5. 生成方案评审报告

按以下维度输出结构化报告：

---

#### 一、Issue 概述

用 2-3 段话概述：
- 问题背景和现状痛点
- 提议方案的核心思路
- 预期收益

#### 二、方案可行性分析

结合 monorepo 现有代码评估：

**与现有架构的兼容性**
- 方案是否与现有架构风格一致？
- 是否需要修改公共接口或数据结构？
- 对现有模块的侵入程度如何？
- 是否有向后兼容性问题？

**技术可行性**
- 方案中的关键技术点是否可实现？
- 是否有已知的技术限制或依赖约束？
- 实现复杂度评估（简单/中等/复杂）

**工作量评估**
- 预估涉及的文件数和改动量
- 是否需要数据迁移或配置变更
- 测试覆盖的工作量

#### 三、方案优势

逐条列出方案的优点：
- ✅ 优势 + 具体理由 + 对比现状的改进

#### 四、方案劣势与风险

逐条列出方案的缺点和潜在风险：

**设计层面**
- 是否过度设计或设计不足？
- 抽象层次是否合理？
- 是否引入不必要的复杂度？

**性能层面**
- 是否有性能退化风险？
- 大数据量场景下的表现？
- 资源消耗（内存、CPU、网络、Token）变化？

**可维护性**
- 是否增加了维护负担？
- 新增概念/抽象是否易于理解？
- 调试和排查问题的难度？

**运维层面**
- 部署和回滚的复杂度？
- 监控和告警是否需要调整？
- 配置管理的变化？

输出格式：
- ⚠️ 风险/劣势 + 具体分析 + 影响范围
- 💡 缓解建议（如有）

#### 五、替代方案建议

如果有更优或值得考虑的替代方案：
- 🔄 替代方案描述 + 优劣对比 + 适用场景

如果当前方案已是最优，明确说明。

#### 六、实施建议

如果方案可行，给出实施建议：
- 建议的实施步骤和优先级
- 需要特别注意的坑点
- 建议的测试策略
- 是否需要分阶段上线（feature flag / 灰度）

---

### 6. 输出最终报告

将所有维度的分析结果合并为一份完整报告，在终端直接输出。

### 7. 归档分析报告

报告输出后，同时保存为 Markdown 文件到 `~/issue_review/` 目录备案：
- 文件名格式：`<repo>_ISSUE<number>_<title>_<YYYYMMDD>.md`
- repo 名从 Issue URL 中提取
- title 从 Issue 元数据中获取，去掉特殊字符，空格替换为 `-`，截断到 50 字符以内
- 如果目录不存在则自动创建

**重新 Review 时保留历史报告**：写入新报告前，检查目录下是否已存在同名文件。如果存在，将旧文件重命名为 `_bakNNN` 格式保留（NNN 为三位数序号，从 001 递增）。

### 8. 发布分析报告到 Issue Comment

归档完成后，将完整报告作为 Issue comment 发布：
```bash
gh issue comment <ISSUE_NUMBER> --repo <OWNER/REPO> --body-file <归档的md文件路径>
```

---

## 审查原则

1. **基于代码说话**：所有分析必须结合 monorepo 现有代码，不做空泛评论
2. **务实导向**：关注方案能否落地，而非理论上的完美
3. **给出替代**：指出问题时附带替代方案或改进建议
4. **理解约束**：考虑团队现状、技术栈限制、时间压力等现实因素
5. **中文输出**：报告使用中文

## Gotchas

1. **Issue 内容不足**：如果 Issue 描述过于简略，先从评论中补充信息；仍不足时在报告中标注"信息不足，以下分析基于有限信息"。
2. **monorepo 代码获取**：优先使用本地代码（如果在 monorepo 目录下）；否则通过 `gh api` 获取远程文件内容。
3. **私有仓库**：`web_fetch` 无法访问私有仓库，必须使用 `gh` CLI。
4. **大文件**：通过 `gh api` 获取文件时注意大小限制，超大文件按需截取关键部分。
5. **多方案 Issue**：如果 Issue 中讨论了多个方案，逐一分析并给出推荐。
