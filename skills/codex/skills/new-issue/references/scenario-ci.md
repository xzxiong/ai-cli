# Scenario: CI failure → issue

**When**: GitHub Actions failure URL, Moi-Core CI, unit/integration/lint/doc/compile failures, runner OOM/timeout/resource evidence from CI.  
**Also triggered by**: standalone skill `/ci-issue`, phrases `ci issue`, `new ci issue` + Actions URL.  
**Default repo**: `matrixorigin/matrixflow` unless the URL names another repo.  
**Default Issue Type**: `Bug`  
**Default create labels** (only if they exist on the repo): `kind/bug-moi`, `kind/bug`  
**Default assignee** (when creating from CI skill path): `xzxiong` unless user overrides.

Do **not** use this for product BVT pytest suites that need `bvt-tag-issue` — use `scenario-bvt.md`.

---

## Workflow (analysis first)

### 1. Parse URL & metadata

```bash
# URL patterns:
#   actions/runs/<run-id>
#   actions/runs/<run-id>/job/<job-id>
repo="matrixorigin/matrixflow"   # override from URL if needed
run_id="<run-id>"

gh api "repos/$repo/actions/runs/$run_id" \
  --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch, name, display_title, event}'
```

Collect: failed jobs, failed steps (`--paginate`), check-run annotations (compiler/test messages).

### 2. Tiered log analysis (gh-first)

**Tier 1 — API/annotations (fast)**  
Failed jobs/steps + annotations. If annotations alone pin the root error, still download artifacts when available for confirmation.

**Tier 2 — Artifacts (primary for Moi-Core)**

```bash
work="/tmp/ci-issue-${run_id}"
mkdir -p "$work"
gh run download "$run_id" -R "$repo" -n moi-core-ci-artifacts -D "$work/artifacts" || true
# list before assuming paths
find "$work" -type f | head -200
```

Typical Moi-Core paths (names evolve — discover with `find`/`rg --files`):

- `logs/ci-exit-code`, `logs/ci-failed-targets.txt`, `logs/ci-failure-summary.txt`
- `logs/ci-test-required.log`, `logs/ci-test.log`, `logs/test-python-sdk.log`, `logs/test.log`
- `coverage/logs/*`, `logs/matrixone-stats.log`, `logs/matrixone-*-inspect.json`

Scan for:  
`FAIL|ERROR|undefined|cannot use|has no field|panic|Traceback|exit status|connection refused|bind: address already in use|timeout|OOM|throttl`

**Tier 3 — Full/failed logs**

```bash
# Prefer full job log when scheduling/LOAD context matters
gh run view "$run_id" -R "$repo" --job "<job-id>" --log
# Fallback
timeout 1800 gh run view "$run_id" -R "$repo" --log-failed
```

### 3. Classify failure

| Type | Signals | Where |
|------|---------|--------|
| Go compile | `undefined`, `cannot use`, `has no field` | test logs |
| Doc inconsistency | `make doc-update` | ci-test |
| Lint | `golangci-lint`, `staticcheck` | ci-test |
| Unit / integration | `--- FAIL:`, package FAIL | test / tests |
| Python SDK | `FAILED`, `AssertionError` | test-python-sdk |
| MatrixOne startup | `wait-mo`, early connection refused | early logs |
| Port conflict | `bind: address already in use` | any + port map |
| Timeout | `exit 124`, `CI_TEST_TIMEOUT` | wrapper / job |
| Infra / resource | cgroup throttle, OOMKilled, runner cancel | LOAD / stats / inspect |

### 4. Port → module (connection errors)

| Port | Module |
|------|--------|
| 8081 | moi-core/catalog HTTP (cmux may share gRPC) |
| 8082 | moi-core/catalog gRPC (non-embedded) |
| 50051 | moi-core/mowl gRPC |
| 6001 | MatrixOne main |
| 6002 | MatrixOne exclusive |
| 6003 | MatrixOne DDL |
| 8000 | local-service |
| 8910 | workflow_be / byoa api-server |
| 9000 | connector_rpc |

### 5. Moi-Core resource analysis (timeout / slow / MO fail)

Before claiming "CPU high" or "timeout root cause", inspect:

1. **Scheduler / runner cgroup** in `ci-test-required.log`: `START`/`END`/`POOL`/`LOAD`  
   LOAD fields: `gomaxprocs`, `cgroup_mem_*`, `cgroup_cpu_*`, `cgroup_cpu_nr_throttled`
2. **MatrixOne container samples** in `matrixone-stats.log` (same timestamp when summing containers)
3. **Limits / OOM** in `matrixone-*-inspect.json` and docker logs (`OOMKilled`, `HostConfig.Memory`, `NanoCpus`, ...)
4. **Test plan** `ci-test-plan.json` — which lane (Go / mo_exclusive / Python / DDL) was active; parallel vs serialized vs canceled

### 6. Evidence boundaries (do not over-claim)

- `exit 124` = GNU timeout budget exceeded — **not** proof the last assertion failed.
- Zero `cgroup_cpu_throttled_usec` = sampled cgroup not throttled — **not** proof of no host contention/disk/PSI.
- `OOMKilled=false` and unset limits do **not** rule out host pressure.
- Green runs often **lack** matrixone-stats artifacts; say so and use LOAD/job logs only.
- Compare with ≥1 successful run of same workflow/runner class when claiming regression; different SHA only for phase contrast unless evidence ties to the PR.

### 7. Dedup then create

```bash
gh issue list -R "$repo" --search "<error keywords> OR <test name>" --state open --limit 10
```

Create only when user asked for an issue (standalone `/ci-issue` implies create; generic analysis may stop at report).

Use helper after create:

```bash
helper=.../new-issue/scripts/apply-matrixone-defaults.sh
"$helper" --repo "$repo" --issue "$issue_number" --type bug
# optional: --labels kind/bug-moi,kind/bug  if labels_mode supports explicit list
```

Also apply assignee when requested: `gh issue edit "$issue_number" -R "$repo" --add-assignee xzxiong`

### 8. Gist + analysis comment

```bash
gh gist create --public --desc "CI Issue #${issue_number} - ${workflow} run ${run_id}" <useful-log-files>
gh issue comment "$issue_number" -R "$repo" --body-file "$work/comment.md"
```

Comment structure (≤ ~60KB): Failed Jobs → Annotations → Stage Errors → Port/Service → Resource evidence → Root cause (facts vs unknowns) → Fix direction.

Temp dir: `/tmp/ci-issue-<run-id>/` — clean up after post unless follow-up needed.

---

## Title

`[CI BUG]: <workflow-name> - <failure-summary>`

---

## Body template (core six adapted for CI)

```markdown
## 摘要

<workflow> on <branch>@<sha> failed: <one-line failure>.

---

## 目标

- 修复使同 workflow 在同类 runner 上稳定通过（或明确为 flaky 并加隔离）
- 保留可复现的失败证据（run URL + gist）

### 非目标

- 不在本 issue 扩 scope 到无关重构

---

## 名词解释

| 名词 | 含义 |
|------|------|
| **run / job / step** | Actions 层级 |
| **LOAD** | runner 侧资源采样行 |
| **lane / pool** | Moi-Core 测试分路与并发池 |
| **exit 124** | GNU timeout 超时 |

---

## 事实依据

### Run 元数据

| 字段 | 值 |
|------|----|
| repo | matrixorigin/matrixflow |
| run URL | |
| workflow | |
| event | |
| branch / sha | |
| conclusion | |
| runner label | |
| 失败 job / step | |
| 起止时间 | |

### 失败分类

- 类型：compile / lint / doc / unit / integration / python-sdk / mo-startup / port / timeout / resource / cancel
- 关键错误原文：

```text
```

### 复现

```bash
# 本地或 CI 复现命令（若已知）
```

### 证据命令 / 路径

```bash
gh run view <run-id> -R matrixorigin/matrixflow --log-failed
# artifact paths used:
```

### 已排除

- ...

---

## 数据依据

| 指标 | 值 | 来源 |
|------|----|------|
| job 时长 | | Actions |
| timeout budget | | workflow / CI_TEST_TIMEOUT |
| cgroup mem current/max | | LOAD |
| cgroup cpu throttled | | LOAD |
| MO container CPU%/Mem | | matrixone-stats |
| OOMKilled | | inspect |

对比成功 run（如有）：

| 项 | 失败 run | 成功 run |
|----|----------|----------|
| sha | | |
| 时长 | | |
| 失败阶段 | | |

待补齐：

- ...

---

## 方案（预案）

### 短期

- 重跑 / 隔离 flaky / 降并发 / 加 timeout 证据采集

### 根治

- ...

### 备选

- ...

### 回滚

- ...

---

## 测试方案

| 场景 | 期望 |
|------|------|
| 同 sha 重跑（若怀疑 infra flake） | 通过或同点失败 |
| 修复后 moi-core-ci / 相关 job | 绿 |
| 资源类修复 | LOAD/stats 无 OOM/异常 throttle；时长回归可接受 |

---

## 验收标准

- [ ] 根因有日志/artifact 引用，不单靠猜测
- [ ] 修复后目标 workflow 通过或 flaky 有独立跟踪
- [ ] 关键日志 gist 已挂 issue（如创建时上传）

---

## 关联

- Run URL：
- Gist：
- 相关 PR / issue：
```

---

## Standalone entry points

| Entry | Behavior |
|-------|----------|
| `/ci-issue <url>` | Full workflow: analyze + create issue + comment (user intent = create) |
| `new-issue` + CI URL | Same scenario file; still ask before create unless user said 直接创建 |
| Analysis only | Stop after report; no issue/gist/comment |

External writes (issue, gist, comment) require explicit user intent or `/ci-issue` invocation.
