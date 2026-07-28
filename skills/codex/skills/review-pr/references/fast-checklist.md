# Fast Mode - Static Review Checklist

Use Fast mode only when the user selects `--fast`. It is a quick, evidence-backed static review, not a replacement for full validation.

## Hard Limits

- Do not run any test command or test script.
- Do not trigger, retry, or wait for CI/test jobs.
- Do not load `section-testing.md` or produce a test-plan/coverage assessment.
- You may read changed test files or nearby test code only to understand the changed contract. Do not infer that tests passed from their presence.
- Do not claim test, CI, runtime, or end-to-end validation.

## Review Priorities

Focus on the smallest set of high-confidence findings that a reviewer can establish from the diff and necessary surrounding code:

- correctness regressions, broken error paths, and unsafe boundary handling
- authentication, authorization, secret, and input-validation risks
- API, schema, configuration, and compatibility breaks
- unbounded retries, loops, fan-out, resource leaks, and concurrency hazards
- new runtime configuration without the mandatory adjacent explanation required by `SKILL.md`

Skip exhaustive style, naming, test-coverage, and speculative architecture feedback. Read surrounding code before reporting a defect and prefer one proven finding over several weak ones.

## Report Shape

```markdown
# Fast Review: <PR title>

PR 基础信息
- **模式**: ⚡ Fast Review（静态审查）
- **测试**: 未执行（`--fast` 模式）

## 〇、总结（TL;DR）
- 一句话概括变更和静态审查结论
- 🔴 / 🟡 / 🟢 发现数量
- 合并建议；若建议合并，必须注明“基于静态审查，测试未执行”

## 一、关键发现
按严重级别列出有文件/行证据的高信号问题。无问题时明确说明“未发现可从静态审查证实的阻塞问题”。

## 二、审查边界
- 已检查：<diff、相关调用方、配置链路等>
- 未执行：测试、CI 重跑、运行时/E2E 验证
```

Each finding follows the main skill's `I-N` numbering and must include the affected file/line, impact, and practical fix.
