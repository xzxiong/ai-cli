# Scenario: Performance

**When**: slow path, p95/p99, cold start, upgrade wall time, throughput regression.  
**Default Issue Type**: `Bug` (regression) or `Task` (planned optimization)  
**Gold style**: matrixflow#13296, #14746

## Title

- `perf: <component> <metric> <observed vs expected>`
- Or narrative with numbers: `prod catalog upgrade took 30+min: ...`

## Labels / defaults hints

- `--type bug` if user-visible regression; else `task`
- Priority from user impact and frequency

## Body template

```markdown
## 摘要

<什么路径慢、慢多少、相对什么基线。>

---

## 目标

1. 延迟 / 吞吐目标（带单位）：...
2. 冷启动 / p95 / 墙钟目标：...
3. 观测可解释：...

### 非目标

- 不改算法精度 / 不扩 scope 的项

---

## 名词解释

| 名词 | 含义 |
|------|------|
| 墙钟 / RTF / p95 / stage | |

---

## 事实依据

### 环境

| 字段 | 值 |
|------|----|
| 环境 / 集群 / ns / 组件 | |
| 镜像 / 版本 | |
| 样本 request / file / job id | |
| 观测时间 | |

### 调用链 / 阶段拆分

| 阶段 | 起止 | 耗时 | 证据 |
|------|------|------|------|
| | | | log line / metric |

### 配置

```yaml
```

### 日志原文（关键段）

```text
```

### 复现 / 取证命令

```bash
```

---

## 数据依据

| 指标 | 当前 | 目标 | 来源 |
|------|------|------|------|
| e2e 墙钟 | | | |
| 主导阶段耗时 | | | |
| tok/s / QPS / 并发 | | | |

Grafana / PromQL（如有）：

```text
```

待补齐：

- ...

---

## 方案（预案）

### P0（立刻）

- ...

### P1

- ...

### P2 / 备选

- ...

推荐顺序：...

回滚：...

---

## 测试方案

| 场景 | 方法 | 通过标准 |
|------|------|----------|
| 对照实验 | 同输入 before/after | 主导阶段 ≤ 目标 |
| 并发 / 限流 | | |
| 无外网 / 冷启动 | | |
| 回归正确性 | | 结果不变 |

---

## 验收标准

- [ ] 主导瓶颈阶段达到目标
- [ ] e2e 达到目标或文档化剩余瓶颈
- [ ] 指标/看板可证明改善

---

## 关联

- ...
```

## Scenario-specific rules

- **Never invent p50/p95**. Missing → 待采集 table with collection method.
- Separate wall-clock stages; name the **dominant** stage.
- Trace metrics to recording points when Grafana values look wrong (bucket interpolation, retries included, etc.).
- If the slowdown is only observed in GitHub Actions, also read `scenario-ci.md` for artifact/LOAD evidence; body may still use this perf template.
