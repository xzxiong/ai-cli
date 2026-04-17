---
name: run-all-tasks
description: |
  自动执行 spec 中的所有 tasks，支持断点续跑。通过 tasks.md 中的 checkbox 状态追踪进度，
  网络断开重连后只需说 "继续" 即可从上次中断的 task 恢复执行。

  Use this skill when:
  - The user says "run all tasks" or "执行所有任务"
  - The user invokes `/run-all-tasks`
  - The user says "run tasks" or "跑任务"
  - The user says "继续" or "continue" (resume from last checkpoint)
  - The user says "继续执行" or "resume tasks"
---

# Run All Tasks — 断点续跑 Spec 任务执行器

## Purpose

自动执行当前 spec 的所有 tasks，通过 tasks.md 中的 `- [ ]` / `- [x]` checkbox 追踪进度。
网络断开后重连，只需说"继续"即可从上次中断处恢复，无需重头开始。

## 核心机制：Checkpoint 驱动的断点续跑

进度持久化在 tasks.md 文件中：
- `- [ ]` = 未完成
- `- [x]` = 已完成
- `- [ ]*` = 可选任务（标记 `*` 的任务默认跳过，除非用户明确要求）

每完成一个 task，立即将其 checkbox 更新为 `- [x]`，这样即使通信中断，下次恢复时能准确知道从哪里继续。

## When Invoked

| 触发方式 | 行为 |
|---------|------|
| `run all tasks` / `执行所有任务` / `跑任务` | 从第一个未完成的 task 开始执行 |
| `继续` / `continue` / `resume tasks` | 等同于上面，从第一个未完成的 task 继续 |
| `run task N` / `执行任务 N` | 执行指定编号的 task |

## Process

### Step 0: 定位 Spec

1. 查找当前活跃的 spec：
   - 检查 `.kiro/specs/` 目录下的所有 spec
   - 如果只有一个 spec，直接使用
   - 如果有多个 spec，检查用户消息中是否指定了 spec 名称
   - 如果未指定且有多个，列出所有 spec 让用户选择
2. 读取 `tasks.md` 文件

### Step 1: 解析 Tasks 状态

扫描 tasks.md，解析所有 task 的状态：

```
Task 1: [x] 已完成
Task 2: [x] 已完成
Task 2.1: [x] 已完成
Task 2.2: [ ] ← 下一个要执行的
Task 3: [ ] 待执行
...
```

规则：
- 顶层 task 格式: `- [ ] N. 描述` 或 `- [x] N. 描述`
- 子 task 格式: `- [ ] N.M 描述` 或 `- [x] N.M 描述`
- 可选 task 格式: `- [ ]* N.M 描述`（带 `*` 标记）
- 找到第一个 `- [ ]`（非 `*` 标记）的 task 作为起始点

### Step 2: 执行 Task

对每个待执行的 task：

1. **输出当前进度**:
   ```
   ━━━ Task {N} / {Total}: {描述} ━━━
   进度: {已完成数}/{总数} ({百分比}%)
   ```

2. **读取 task 详情**: 解析 task 下的所有子项和说明

3. **执行 task 内容**:
   - 读取需要修改的文件
   - 按照 task 描述进行代码修改
   - 如果是 Checkpoint task，运行编译检查

4. **标记完成**: 将 `- [ ]` 更新为 `- [x]`
   ```
   # 更新 tasks.md 中对应行
   - [ ] 2.2 新增 ACMETLSConfig 结构体
   →
   - [x] 2.2 新增 ACMETLSConfig 结构体
   ```

5. **继续下一个 task**

### Step 3: Checkpoint 处理

遇到 Checkpoint task 时（描述中包含 "Checkpoint" 或 "确保编译通过"）：

1. 运行编译检查:
   ```bash
   # Go 项目
   go build ./...
   
   # 或使用 getDiagnostics 检查
   ```

2. 如果编译失败:
   - 分析错误信息
   - 尝试自动修复（最多 3 轮）
   - 如果无法自动修复，停止执行并报告给用户

3. 编译通过后标记 Checkpoint 完成

### Step 4: 可选 Task 处理

标记 `*` 的可选 task（如 `- [ ]* 10.1`）：
- 默认跳过，不执行
- 在输出中标注 "已跳过（可选）"
- 如果用户明确要求执行可选 task，则执行

### Step 5: 完成报告

所有 task 执行完毕后，输出简洁总结：

```
✅ Spec 任务全部完成

已完成: {N} 个 task
已跳过: {M} 个可选 task
修改文件: file1, file2, ...
```

## 断点续跑示例

```
# 第一次执行（在 Task 4 时网络断开）
User: run all tasks
Agent: [执行 Task 1... ✅]
       [执行 Task 2... ✅]
       [执行 Task 3... ✅]
       [执行 Task 4...] ← 网络断开

# tasks.md 此时状态:
# - [x] 1. 输出设计文档
# - [x] 2. 扩展数据模型
# - [x] 3. CRD 前置检查
# - [ ] 4. 重构 deployTLSInfra  ← 可能部分完成

# 重连后
User: 继续
Agent: [读取 tasks.md，发现 Task 4 未标记完成]
       [从 Task 4 开始继续执行]
       ━━━ Task 4 / 11: 重构 deployTLSInfra ━━━
       进度: 3/11 (27%)
       [继续执行...]
```

## 关键规则

1. **每完成一个 task 立即更新 tasks.md** — 这是断点续跑的基础
2. **子 task 全部完成后才标记父 task 完成** — 保证粒度正确
3. **Checkpoint 失败时停止** — 不跳过编译错误继续执行
4. **可选 task 默认跳过** — 除非用户明确要求
5. **读取现有代码再修改** — 每个 task 开始时先读取目标文件的当前状态，避免基于过期内容修改
6. **遵循 tasks.md 中的文件路径** — 所有路径以 tasks.md 中指定的为准

## 与其他 Skill 的关系

- 本 skill 执行的是 `spec-worktree` skill 创建的 spec 中的 tasks
- 执行完成后可以用 `git-push-pr` skill 提交代码
- 如果 task 涉及测试，可以用 `test-debug-fix` skill 处理测试失败

## Hook 配置（每个仓库需单独添加）

Hooks 只在 workspace 级别生效。要启用断线自动续跑，需要在仓库的 `.kiro/hooks/` 下创建 `resume-spec-tasks.kiro.hook`：

```json
{
  "enabled": true,
  "name": "Resume Spec Tasks",
  "description": "agent 停止时自动检查并继续未完成的 spec tasks",
  "version": "1",
  "when": { "type": "agentStop" },
  "then": {
    "type": "askAgent",
    "prompt": "检查当前活跃 spec 的 tasks.md 文件（.kiro/specs/*/tasks.md），如果存在未完成的 task（`- [ ]`，不含 `*` 标记的可选任务），说明之前的 run-all-tasks 执行被中断了。请自动继续执行下一个未完成的 task，无需等待用户指令。按照 run-all-tasks skill 的流程继续：读取 task 详情 → 执行修改 → 标记完成 → 继续下一个。如果所有 task 都已完成（`- [x]`），则无需任何操作。"
  }
}
```

当用户说 `run all tasks` 时，如果检测到仓库中没有这个 hook，应主动创建它。

## Implementation Notes

- tasks.md 的 checkbox 更新使用 strReplace 精确替换，避免误改其他内容
- 对于有子 task 的父 task，只在所有子 task 完成后才标记父 task
- Checkpoint task 使用 `go build ./...` 或 `getDiagnostics` 验证
- 每个 task 执行前先输出进度信息，方便用户了解当前状态
