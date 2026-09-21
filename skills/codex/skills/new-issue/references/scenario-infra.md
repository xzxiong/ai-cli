# Scenario: Infra / Ops / Design Task

**When**: capacity, deploy, CI infra (not a single failed run), k8s, multi-option platform work.  
**Default Issue Type**: `Task`  
**Gold style**: matrixflow#14671

Read this file only after `new-issue` SKILL.md classified the request as **infra**.

## Title

- `infra(ci): ...` / `ops: ...` / `deploy: ...`
- Specific and searchable; avoid "优化一下"

## Labels / defaults hints

- Prefer `--type task`
- Priority from urgency (capacity risk → p1; cleanup → p2)
- Labels: existing `area/*` only when evidenced; do not invent

## Body template

```markdown
## 背景

<为什么现在要做。引用 parent issue / 评论 / 现网样本。>

### 问题本质

<一句话点破：不是 X，而是 Y。>

---

## 目标

<期望终态，操作化语言。>

成功标准（可测）：

1. ...
2. ...

### 非目标

- ...

---

## 名词解释

| 名词 | 含义 |
|------|------|
| **term** | ... |

---

## 事实依据

### 1) 环境 / 对象

| 字段 | 值 |
|------|----|
| 环境 | dev / qa / prod / IDC |
| 集群 / KUBECONFIG | |
| namespace | |
| 组件 / Pod / label | |
| 镜像 / 版本 | |
| 发生或观测时间 | |
| 配置来源路径 | `path/to/file` |

### 2) 配置（原文）

```yaml
# path/to/values-or-pulumi.yaml
```

### 3) 代码 / 行为（可核对）

- `path:symbol` — <一句话行为>

### 4) 现网观测 / 复现命令

```bash
# 可复跑命令
```

```text
# 关键日志 / kubectl 输出原文（脱敏）
```

### 5) 已排除

- ...

---

## 数据依据

> 无数据时保留本节，改成「待补齐的基线」表，禁止编造 p50/p95。

| 指标 | 来源 | 当前值 | 用途 |
|------|------|--------|------|
| | Prometheus / log / GH Actions / Grafana | | |

**基线结论模板（落地后填）：**

- ...
- 建议值 / 阈值：...

---

## 方案（预案）

### 方案 A（推荐）：...

1. ...
2. ...

优点 / 风险：...

### 方案 B：...

优点 / 风险：...

### 方案 C（最小 / 仅观测）：...

### 推荐落地顺序

1. Phase 0：...
2. Phase 1：...
3. Phase 2：...

### 回滚

1. ...
2. ...

---

## 任务清单

- [ ] ...
- [ ] ...

---

## 测试方案

### 功能 / 行为

| 场景 | 期望 |
|------|------|
| | |

### 观测验收

- [ ] ...

### 回归 / 压测

1. ...

### 回滚演练

- ...

---

## 验收标准

- [ ] ...
- [ ] ...

---

## 优先级

**P0 / P1 / P2** — <一句话理由>

---

## 关联

- Issue / PR：
- 代码：
- 文档 / handbooks：
- 现网对象：
```

## Scenario-specific rules

- Prefer **≥2 options** in 预案 for production/CI capacity changes.
- Always include **回滚** when changing requests/limits, runner scale, or deploy path.
- 数据依据 must separate **usage** vs **request/limit 账本** when resources are involved.
