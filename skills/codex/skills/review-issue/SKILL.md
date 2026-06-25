---
name: review-issue
description: Deep-review a GitHub issue's technical proposal against the local monorepo codebase, write a Chinese feasibility/risk review, archive it, and post it as an issue comment. Use for `/review-issue` or requests to review a technical方案 in an issue.
---

# Review Issue

Review a GitHub issue's proposed technical plan using local code evidence.

## Workflow

1. Fetch the issue and comments.
2. Extract problem background, proposed solution, affected modules, and key decisions.
3. Search the local monorepo for related implementations, interfaces, and call sites.
4. Evaluate feasibility, compatibility, work estimate, risks, operational impact, and alternatives.
5. Write a Chinese report with:
   - Issue overview.
   - Feasibility analysis.
   - Strengths.
   - Risks and mitigations, covering design, performance, maintainability, and operations.
   - Alternative approaches.
   - Implementation steps, pitfalls, testing strategy, and whether rollout/gray release is needed.
6. Archive under `~/issue_review/<repo>_ISSUE<number>_<title>_<YYYYMMDD>.md`, rotating existing files with `_bakNNN`.
7. Post the report as a GitHub issue comment.

## Principles

- Base conclusions on code, not generic opinions.
- Pair major risks with practical alternatives or mitigations.
- Consider team context and delivery pressure; avoid impractical recommendations.
