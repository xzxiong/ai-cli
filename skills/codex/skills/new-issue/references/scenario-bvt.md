# Scenario: BVT failure → issue

**When**: BVT / pytest product test failure, `test_*.py::test_*`, `bvt-tag-issue`, or user says `bvt issue` / `/bvt-issue`.  
**Also**: `reanalyze #N` / `重新分析 #N` on an existing BVT issue.  
**Default repo**: `matrixorigin/matrixflow`  
**Default Issue Type**: `Bug`  
**Default labels** (if exist): `kind/bug-moi`, `kind/bug`, `bvt-tag-issue`  
**Default assignee**: `xzxiong` unless user overrides.

For pure Moi-Core unit/integration CI without BVT semantics → `scenario-ci.md`.

---

## Modes

| Mode | Trigger | Actions |
|------|---------|---------|
| **New** | failure text ± CI URL | create issue → return URL → analyze → gist/comment |
| **Re-analyze** | `reanalyze` / `re-analyze` / `重新分析` + issue number/URL | skip create; fetch issue; extract CI URL; analyze → comment |

Zero-interaction preference for `/bvt-issue`: extract everything from the first user message; do not block on questions if test name + failure text exist.

---

## New issue workflow

### 1. Extract

- Test case: `test_*.py::test_*`, `FAILED test_*`, `src/tests/.../test_*.py::test_*`
- Full failure message (preserve user text)
- CI Actions URL if present

### 2. Title

`[MOI BUG]: <≤60 chars from test name or first failure line>`

### 3. Create body (quality bar + BVT fields)

Use the template below (core six + BVT-specific information block). Then:

```bash
repo="matrixorigin/matrixflow"
issue_url="$(gh issue create -R "$repo" --title "$title" --body-file "$body_file")"
issue_number="$(gh issue view "$issue_url" -R "$repo" --json number -q .number)"

# labels if present on repo
gh issue edit "$issue_number" -R "$repo" \
  --add-label "kind/bug-moi" --add-label "kind/bug" --add-label "bvt-tag-issue" 2>/dev/null || true
gh issue edit "$issue_number" -R "$repo" --add-assignee xzxiong 2>/dev/null || true

helper=.../new-issue/scripts/apply-matrixone-defaults.sh
"$helper" --repo "$repo" --issue "$issue_number" --type bug
```

**Return issue URL immediately**, then continue analysis (user should not wait for full log download).

---

## Re-analysis workflow

```bash
gh issue view "$n" -R matrixorigin/matrixflow --json title,body,comments
# extract actions/runs/<id> from body/comments
```

Then run the same tiered analysis and post a new comment (no second issue).

---

## Post-create analysis (tiered)

**Tier 1 — gh API (~5s)**  
Run metadata, failed jobs/steps, check-run annotations (assertion, file, test name). If annotations are enough for a clear test failure, still prefer downloading BVT artifacts when cheap.

**Tier 2 — failed step logs**

```bash
timeout 1800 gh run view "$run_id" -R matrixorigin/matrixflow --log-failed
```

**Tier 3 — artifacts (~2–5min)**  
Download `logs` and `bvt-runlog` (names may vary — list artifacts first):

```bash
work="/tmp/bvt-analysis-${run_id}"
mkdir -p "$work"
gh run view "$run_id" -R matrixorigin/matrixflow --json artifacts
gh run download "$run_id" -R matrixorigin/matrixflow -n logs -D "$work" || true
gh run download "$run_id" -R matrixorigin/matrixflow -n bvt-runlog -D "$work" || true
```

Decision: annotations sufficient → draft comment early; empty annotations → Tier 2; empty/timeout → Tier 3. Prefer parallel artifact download when likely needed.

### Port → service (BVT stack)

| Port | Service | Typical log |
|------|---------|-------------|
| 8910 | byoa / api-server | apiserver.log |
| 8911 | byoa / job-consumer | job_consumer.*.log |
| 9000 | connector-rpc | connector.log |
| 6001 | MatrixOne | matrixflow-mo.log |
| 50051 / 50052 | mowl | mowl.log |

On `127.0.0.1:PORT: connection reset/refused`, map port → prioritize that service log ±2 minutes around failure.

### Gist + comment

```bash
gh gist create --public --desc "BVT Issue #${issue_number} - CI logs for run ${run_id}" <files...>
gh issue comment "$issue_number" -R matrixorigin/matrixflow --body-file "$work/comment.md"
```

Comment structure (≤ ~60KB): Run info → Failed jobs/steps → Annotations → Suspected service → CI step errors → Pytest summary → Service log errors → Root cause / next fix.

Temp: `/tmp/bvt-analysis-<run-id>/` — clean after post.

---

## Body template

```markdown
## 摘要

BVT `<test_node_id>` failed: <one-line assertion/error>.

---

## 目标

- 修复产品/测试问题使该 case 稳定通过
- 用 CI 日志定位责任服务，避免只贴 pytest 失败行

### 非目标

- 不把 Moi-Core 纯单测失败当 BVT（应走 CI 场景）

---

## 名词解释

| 名词 | 含义 |
|------|------|
| **BVT** | 产品级端到端 / 行为验证测试 |
| **node id** | `file.py::test_name` |
| **job-consumer** | 异步任务消费（常与 8911 相关） |

---

## 事实依据

### BVT 信息

| 字段 | 值 |
|------|----|
| env | ci |
| test case | `path/test_foo.py::test_bar` |
| CI run URL | |
| query_id | N/A |
| instance_id | N/A |
| instance_link | N/A |

### 失败原文（完整保留）

```text
<full user message / pytest failure>
```

### 复现步骤

1. Run BVT suite (or CI workflow that executes this case)
2. Execute: `<test node id>`
3. Observe: <failure>

### 服务侧线索（分析后填）

- 怀疑服务 / 端口：
- 关键日志片段：

```text
```

---

## 数据依据

| 项 | 值 | 来源 |
|----|----|------|
| 失败 step 时长 | | Actions |
| 同 case 历史失败次数 | | issue search / CI（若查了） |
| 关联服务 error 计数 | | service log |

待补齐：

- ...

---

## 方案（预案）

### 产品 bug

- ...

### 测试不稳定 / 环境

- ...

### 短期缓解

- skip / quarantine / retry policy（需说明代价）

---

## 测试方案

| 场景 | 期望 |
|------|------|
| 单 case 复跑 | 通过 |
| 相关 BVT 子集 | 无新增失败 |
| 修复后 CI | 同 workflow 绿 |

---

## 验收标准

- [ ] 原 test node 通过
- [ ] 根因有服务日志或明确测试问题证据
- [ ] 分析 comment + 必要 gist 已挂上

---

## 关联

- CI URL：
- Gist：
- 相关 issue/PR：
```

Legacy short body (only if user demands minimal / automation compatibility) may keep:

```markdown
**information**
- env: ci
- query_id: N/A
- instance_id: N/A
- instance_link: N/A

**Describe the bug**
...

**How To Reproduce The Bug Step By Step**
1. Run BVT test suite
2. Execute case: <test>
3. Observe the failure
```

Prefer the full core-six template above for human-created issues.

---

## Standalone entry points

| Entry | Behavior |
|-------|----------|
| `/bvt-issue <text>` | Create immediately + analyze + comment |
| `new-issue` + BVT failure | Load this scenario; create per user intent |
| `reanalyze #N` | Analysis comment only |
