---
name: new-issue
description: Create a high-quality GitHub issue from investigation, requirements, CI/BVT failures, or a proposed change. Prefer this skill for "new issue", "create issue", "file issue", "提 issue", "建 issue", "开 issue", CI/BVT failure URLs that should become issues, or pastes that should be tracked. Bodies must include 目标, 名词解释, 事实依据, 数据依据, 预案, and 测试方案 when warranted. Scenario details live in separate reference files — load only the matched scenario. For MatrixOrigin repositories, add the issue to New MatrixOne Intelligence and apply Issue Type, Priority, Iteration, 视角, and initial Labels.
---

# New Issue

Create an **evidence-backed, actionable** issue. This file is the **router + shared workflow**. Scenario-specific templates and analysis steps live in **separate** `references/scenario-*.md` files — **read only the one you need** (do not load every scenario into context).

## Quality bar (non-negotiable)

An issue is not ready if a reader must re-investigate basic context. Core dimensions:

| Dimension | Required content |
|-----------|------------------|
| **目标** | Measurable success criteria; **非目标** when scope must stay tight |
| **名词解释** | Domain terms used later (tables) |
| **事实依据** | Real config, code paths, logs/commands, env, run URLs |
| **数据依据** | Numbers with sources; **待采集** if missing — never invent |
| **预案** | Ranked options + recommendation; rollback when risky |
| **测试方案** | Prove fix + regressions + observability |

Shared checklist: `references/quality-checklist.md` (read before create if unsure).

Do **not** invent evidence. Prefer original snippets. Redact secrets.

## Create workflow

1. **Classify** → pick **one** scenario file (table below) and **Read that file**.
2. **Dedup**: `gh issue list --repo "$repo" --search "<keywords>" --state open --limit 10`.
3. **Gather evidence** per the scenario (CI/BVT have tiered log steps).
4. **Write body** from that scenario's template. Keep honest `待补齐` rather than dropping core sections.
5. **Preview** title + body when long or user did not say 直接创建 / just create (exception: `/ci-issue` and `/bvt-issue` default to create).
6. **Create** with explicit `--repo` and `--body-file`.
7. **Apply MatrixOrigin defaults** via `scripts/apply-matrixone-defaults.sh`.
8. CI/BVT scenarios may then **gist + comment** analysis.

```bash
repo="matrixorigin/<repo>"
body_file="$(mktemp /tmp/new-issue-XXXXXX.md)"
# write body into $body_file
issue_url="$(gh issue create --repo "$repo" --title "$title" --body-file "$body_file")"
issue_number="$(gh issue view "$issue_url" --repo "$repo" --json number --jq .number)"

helper="scripts/apply-matrixone-defaults.sh"
if [[ ! -x "$helper" ]]; then
  for c in \
    /data2/xzxiong/.claude/skills/new-issue/scripts/apply-matrixone-defaults.sh \
    /data2/xzxiong/.codex/skills/new-issue/scripts/apply-matrixone-defaults.sh
  do
    [[ -x "$c" ]] && helper="$c" && break
  done
fi
"$helper" --repo "$repo" --issue "$issue_number"
```

Run the same script when the request is only to apply or correct initial metadata.

## Scenario router (load exactly one)

| Scenario | Signals | Read |
|----------|---------|------|
| **ci** | Actions run/job URL; Moi-Core CI; unit/integration/lint/doc/compile; CI OOM/timeout/LOAD; `/ci-issue` | `references/scenario-ci.md` |
| **bvt** | BVT/pytest product failure; `test_*.py::test_*`; `bvt-tag-issue`; `/bvt-issue`; `reanalyze #N` | `references/scenario-bvt.md` |
| **perf** | p95/slow/cold start/upgrade wall time (product or service path) | `references/scenario-perf.md` |
| **infra** | Capacity, deploy, k8s, multi-option platform design (not a single failed run) | `references/scenario-infra.md` |
| **bug** | Wrong behavior / crash / outage (not CI/BVT-primary) | `references/scenario-bug.md` |
| **feature** | New capability | `references/scenario-feature.md` |
| **docs** | Pure docs/chore / user asks for short note | `references/scenario-docs.md` |

### Disambiguation

- **CI vs BVT**: BVT product suite + `bvt-tag-issue` path → **bvt**. Moi-Core / generic Actions failure → **ci**. If both, prefer **bvt** when the failing node is a BVT pytest case.
- **CI timeout that is really capacity design** (change runners/resources long-term) → create with **ci** evidence, or follow-up design issue with **infra**.
- **Perf seen only in CI logs** → body can follow **perf**, but gather evidence using **ci** artifact steps (read both only if needed: ci for collection, perf for body shape).

Standalone skills **`ci-issue`** and **`bvt-issue`** are thin entry points into the **ci** / **bvt** scenarios of this skill (same templates and MatrixOrigin defaults).

## Core section order (default)

Unless the scenario template says otherwise:

1. 背景 or 摘要  
2. 目标 (+ 非目标)  
3. 名词解释  
4. 事实依据  
5. 数据依据  
6. 方案（预案）  
7. 任务清单 (if useful)  
8. 测试方案  
9. 验收标准  
10. 优先级 / 关联  

### Writing rules (short)

- **目标**: operational end state + pass/fail criteria.  
- **名词解释**: only terms used later.  
- **事实依据**: checkable env/config/code/log/repro/run URL.  
- **数据依据**: units + source; 待采集 table if missing.  
- **预案**: ≥2 options when non-trivial; mark 推荐; rollback when deploy/CI capacity.  
- **测试方案**: map to 验收标准.

## Title

Specific and searchable. Examples:

- `infra(ci): 规范 IDC dind runner 资源使用与资源观测`
- `[CI BUG]: Moi-Core CI - undefined: Foo`
- `[MOI BUG]: test_foo.py::test_bar assertion`

## MatrixOrigin defaults

Helper is idempotent; only mutates `matrixorigin/*` repos:

- Project: `New MatrixOne Intelligence`
- Issue Type, Priority, active Iteration, 视角=`开发实现`
- Conservative existing Labels (`kind/*`, `needs-triage`, evidenced `area/*`)

Overrides: `--type bug|feature|task`, `--priority p0|p1|p2`, `--iteration '<title>'`, `--labels auto|none|a,b`.

```bash
scripts/apply-matrixone-defaults.sh --repo matrixorigin/matrixone --issue 12345 --type bug --priority p1
```

Missing project scope:

```bash
gh auth refresh -s project
```

Do not claim full creation until the helper reports Project / Type / Priority / Iteration / 视角 / Labels (or states what failed).

## Thin vs full

| Request | Depth |
|---------|--------|
| Full investigation paste | Full scenario template |
| `/ci-issue` / `/bvt-issue` | Scenario default (create + analyze) |
| "简单记一下" / pure docs | `scenario-docs.md` |
| Unsure | Prefer full core sections with 待补齐 |

## Self-check

- [ ] Matched **one** scenario file and followed it  
- [ ] Title specific  
- [ ] Core sections honest (no invented data)  
- [ ] Dedup done  
- [ ] Defaults script will run  
- [ ] CI/BVT: analysis comment plan clear  

## Report back

1. Issue URL + number  
2. Scenario used (`ci` / `bvt` / …)  
3. Type / Priority / Iteration / 视角 / Labels  
4. Gist/comment if posted  
5. Body gaps (e.g. 数据依据 待补齐)  
