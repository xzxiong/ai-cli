对 GitHub Issue 中的技术方案进行深度评审，结合 monorepo 现有代码分析可行性。

Input: $ARGUMENTS (Issue URL 或 #number)

## 流程

### 1. 获取 Issue
```bash
gh issue view <number> --repo <OWNER/REPO> --json title,body,labels,state,assignees,comments
gh api repos/<OWNER>/<REPO>/issues/<number>/comments --jq '.[].body'
```

### 2. 提取方案关键信息
- 问题描述、提议方案、涉及模块、关键设计决策

### 3. 定位 monorepo 相关代码
搜索方案涉及的关键类/函数/模块在本地代码中的实现。

### 4. 生成评审报告（中文输出）

#### 一、Issue 概述
问题背景、方案核心思路、预期收益

#### 二、方案可行性分析
- 与现有架构兼容性、技术可行性、工作量评估

#### 三、方案优势
- ✅ 优势 + 理由 + 对比现状

#### 四、方案劣势与风险
- 设计层面、性能层面、可维护性、运维层面
- ⚠️ 风险 + 分析 + 影响范围
- 💡 缓解建议

#### 五、替代方案建议
- 🔄 替代方案 + 优劣对比

#### 六、实施建议
- 实施步骤、坑点、测试策略、是否需灰度

### 5. 归档
保存到 `~/issue_review/<repo>_ISSUE<number>_<title>_<YYYYMMDD>.md`
已存在则重命名旧文件为 `_bakNNN.md` 保留。

### 6. 发布到 Issue
```bash
gh issue comment <number> --repo <OWNER/REPO> --body-file <md文件路径>
```

## 审查原则
1. 基于代码说话，不做空泛评论
2. 务实导向，关注能否落地
3. 指出问题时附带替代方案
4. 考虑团队现状和时间压力
