# Cross-scenario quality checklist

Apply after drafting any scenario body, before `gh issue create`.

| Section | Fail if... |
|---------|------------|
| 目标 | Only "optimize" / "fix" with no measurable end state |
| 名词解释 | Body uses jargon never defined |
| 事实依据 | Only opinions; no path, log, config, run URL, or command |
| 数据依据 | Made-up numbers, or silent omission when perf/capacity/CI duration is the point |
| 预案 | Single vague "we should improve" with no mechanism/rollback when change is risky |
| 测试方案 | "test later" with no scenario or pass criteria |

## Gold examples (tone only)

| Issue | Scenario |
|-------|----------|
| matrixflow#14671 | infra |
| matrixflow#14746 | perf / infra delivery |
| matrixflow#13296 | perf / incident evidence |

## Shared rules

- Do not invent logs, metrics, configs, or IDs.
- Missing evidence → `unknown` / `待补齐` + how to collect.
- Redact secrets; keep searchable ID prefixes.
- Dedup open issues before create.
- MatrixOrigin repos: always run `scripts/apply-matrixone-defaults.sh` after create.
