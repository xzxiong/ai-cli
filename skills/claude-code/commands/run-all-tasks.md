自动执行 spec 中的所有 tasks，通过 tasks.md checkbox 追踪进度，支持断点续跑。

Input: $ARGUMENTS (可选: spec 名称, 或 "继续"/"continue" 从中断处恢复)

## 核心机制：Checkpoint 驱动的断点续跑

进度持久化在 tasks.md 中：
- `- [ ]` = 未完成
- `- [x]` = 已完成
- `- [ ]*` = 可选任务（默认跳过）

每完成一个 task，立即将 checkbox 更新为 `- [x]`。

## 触发行为

| 触发方式 | 行为 |
|---------|------|
| `run all tasks` / `执行所有任务` | 从第一个未完成 task 开始 |
| `继续` / `continue` | 同上，从第一个未完成 task 继续 |
| `run task N` | 执行指定编号的 task |

## 流程

### 0. 定位 Spec
检查 `.kiro/specs/` 下所有 spec。单个直接使用，多个让用户选择。读取 `tasks.md`。

### 1. 解析 Tasks 状态
扫描 tasks.md，找到第一个 `- [ ]`（非 `*` 标记）的 task 作为起始点。
- 顶层: `- [ ] N. 描述`
- 子 task: `- [ ] N.M 描述`
- 可选: `- [ ]* N.M 描述`

### 2. 执行 Task
对每个待执行 task：
1. 输出进度: `━━━ Task {N} / {Total}: {描述} ━━━ 进度: {已完成}/{总数} ({百分比}%)`
2. 读取 task 详情和需要修改的文件
3. 执行代码修改
4. 标记完成: `- [ ]` → `- [x]`
5. 继续下一个

### 3. Checkpoint 处理
遇到 Checkpoint task（描述含 "Checkpoint" 或 "确保编译通过"）：
```bash
go build ./...
```
编译失败: 尝试自动修复（最多 3 轮）。无法修复则停止并报告。

### 4. 可选 Task
标记 `*` 的可选 task 默认跳过，输出 "已跳过（可选）"。用户明确要求时才执行。

### 5. 完成报告
```
✅ Spec 任务全部完成
已完成: {N} 个 task
已跳过: {M} 个可选 task
修改文件: file1, file2, ...
```

## 关键规则

1. 每完成一个 task 立即更新 tasks.md
2. 子 task 全部完成后才标记父 task
3. Checkpoint 失败时停止，不跳过编译错误
4. 可选 task 默认跳过
5. 每个 task 开始时先读取目标文件当前状态
6. 所有路径以 tasks.md 中指定的为准

## 与其他 Skill 的关系

- 执行 `spec-worktree` 创建的 spec 中的 tasks
- 完成后可用 `git-push-pr` 提交代码
- 测试失败可用 `test-debug-fix` 处理
