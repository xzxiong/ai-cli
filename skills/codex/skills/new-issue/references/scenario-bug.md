# Scenario: Bug / Incident

**When**: wrong behavior, crash, outage, data error (not primarily a CI/BVT run failure).  
**Default Issue Type**: `Bug`  
**For CI unit/integration failures** → use `scenario-ci.md`.  
**For BVT pytest product failures** → use `scenario-bvt.md`.

## Title

- `[MOI BUG] <phenomenon>` or concise English/Chinese summary of the failure
- Include component when known: `catalog`, `backend`, `mowl`, ...

## Labels / defaults hints

- `--type bug`
- Priority from impact (prod outage → p0/p1)
- Labels: `kind/bug` / `kind/bug-moi` only if they already exist on the repo

## Body template

```markdown
## 摘要

<谁在什么场景下遇到什么问题；一句话。>

---

## 目标

- 修复：...
- 验证：...
- 防再发（如适用）：...

### 非目标

- ...

---

## 名词解释

| 名词 | 含义 |
|------|------|
| | |

---

## 环境信息

| 字段 | 值 |
|------|----|
| 环境 | 本地 / dev / qa / staging / prod / on-prem / IDC |
| 部署形态 | SaaS / 私有化 / docker / k8s（集群名） |
| 区域/机房 | |
| 产品版本 / 镜像 tag | |
| commit / build | |
| 发生时间（含时区） | |
| 是否可稳定复现 | 总是 / 有时 / 仅一次 / 未知 |
| 复现概率 | |

## 租户与实例（如适用）

| 字段 | 值 |
|------|----|
| workspace_id / tenant_id / instance_id | |
| 相关页面 URL | |
| query_id / request_id / trace_id | |
| workflow_id / task_id / file_id | |

---

## 事实依据

### 期望行为

...

### 实际行为

...

### 复现步骤

1. ...
2. ...
3. 观察到：...

### 配置 / 代码

```text
# 真实配置或路径
```

### 错误信息 / 日志（原文）

```text
```

### 证据命令

```bash
```

---

## 数据依据

| 指标 / 计数 | 来源 | 值 |
|-------------|------|----|
| 影响用户数 / 错误率 / 持续时间 | | |

影响范围：

- **严重程度**：P0 / P1 / P2
- **影响面**：单用户 / 单租户 / 多租户 / 全站
- **业务影响**：不可用 / 结果错误 / 性能下降 / 数据风险 / 体验
- **临时绕过**：有 / 无 — ...

---

## 方案（预案）

### 短期缓解

- ...

### 根治方案

- ...

### 备选

- ...

### 回滚

- ...

---

## 测试方案

| 场景 | 步骤 | 期望 |
|------|------|------|
| 主路径复现 | | 不再出现 |
| 回归 | | |
| 观测 | | 错误日志/指标下降 |

---

## 验收标准

- [ ] 原复现步骤失败条件消失
- [ ] 相关监控/日志无回归
- [ ] ...

---

## 关联

- ...
```

## Scenario-specific rules

- Prefer **original** stack traces and request IDs over paraphrase.
- Unknown fields → `unknown` / `N/A`, never blank invent.
- Redact tokens/passwords; keep enough of IDs to search logs.
