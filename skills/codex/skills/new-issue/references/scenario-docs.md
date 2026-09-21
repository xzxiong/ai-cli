# Scenario: Docs / Chore (thin)

**When**: pure documentation, tiny chore, or user explicitly asks for a short note.  
**Default Issue Type**: `Task`

If the chore touches production resources, CI capacity, or multi-step design, **upgrade to** `scenario-infra.md` before create.

## Title

- `docs: ...` / `chore: ...`

## Body template

```markdown
## 背景

...

## 目标

...

## 事实依据

- 相关路径 / 现状：...

## 方案

...

## 测试方案 / 验收

- [ ] 文档链接可打开 / 命令可跑通
- [ ] ...

## 关联

- ...
```

## Scenario-specific rules

- Still no invented evidence.
- Core six can be collapsed, but keep 目标 + 事实依据 + 验收 at minimum.
- If discussion reveals risk/metrics, reclassify to infra/bug/perf.
