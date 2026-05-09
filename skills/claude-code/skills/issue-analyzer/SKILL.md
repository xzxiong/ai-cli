---
name: issue-analyzer
description: "Analyze a GitHub issue end-to-end: fetch the issue and its comments, locate related source code in the repo or third/ submodules, run k8s diagnostics (pod status, logs, events) using the correct KUBECONFIG, synthesize findings into a structured analysis, and post the result as a comment on the issue. Use this skill whenever the user mentions analyzing an issue, investigating a GitHub issue, diagnosing a pod or service problem referenced in an issue, or wants analysis results posted back to an issue. Also trigger when the user pastes a GitHub issue URL or says something like 'look into issue #N', 'check what's wrong with this issue', or 'analyze and comment on the issue'."
---

# Issue Analyzer

You are an operations engineer for the MOI platform. Your job is to take a GitHub issue, fully investigate it — reading comments, finding relevant code, running k8s diagnostics — and post a structured analysis comment back on the issue.

## Issue Classification

After fetching the issue, classify it to choose the right workflow:

| Type | Signals | Primary Workflow |
|------|---------|-----------------|
| **Crash/Error** | stack trace, panic, crash, 5xx errors | K8s diagnostics → code path → root cause |
| **Performance** | slow, timeout, p95/p99, latency, 耗时 | **Multi-log correlation → metric tracing → bottleneck** |
| **Config/Deploy** | helm, env, config, startup failure | Config diff → gitops check → fix |
| **Feature/Question** | how to, feature request | Brief response, no deep diagnostics |

**For Performance issues**: delegate to the `log-perf-analyze` skill or invoke its workflow inline. Performance issues require multi-service log correlation (job-consumer + llm-proxy + upstream API), metric code tracing, and Prometheus histogram analysis — the standard crash/error workflow is insufficient.

## Context

This skill can operate in two modes:
1. **Within `moi-core-handbooks` repo** — uses `third/` submodules, `docs/analysis/`
2. **Within `matrixflow` repo** — direct access to source code, uses `docs/issue/` for analysis docs

Key resources:
- `docs/analysis/` or `docs/issue/` — existing analysis documents (use as style reference)
- `third/` — git submodules (if in handbooks repo)
- `AGENTS.md` — cluster configs, submodule docs, environment details
- `CLAUDE.md` — project conventions (naming, security, references)

### Environment Map

| Environment | CP Cluster (KUBECONFIG) | DP/Unit Cluster (KUBECONFIG) |
|-------------|------------------------|------------------------------|
| dev | `~/.kube/ack-dev-control-plane` | `~/.kube/ack-unit-hz-new` |
| qa | `~/.kube/ack-qa-control-plane` | `~/.kube/ack-unit-hz-qa` |
| prod | `~/.kube/ack-prod-control-plane` | `~/.kube/ack-prod-unit-hz` |
| IDC | — | `~/.kube/idc-unit` |

### Service → Submodule Map

| Service keyword | Submodule | Key paths |
|----------------|-----------|-----------|
| moi-backend | `third/matrixflow` | `moi-backend/cmd/`, `moi-backend/pkg/` |
| moi-core, explore, catalog, mowl, saga, fileservice, worker | `third/matrixflow` | `moi-core/<service>/` |
| mocloud, billing, instance, admin, auth, cluster, oauth | `third/mocloud-services` | search by service name |
| unit-agent | `third/unit-agent` | root |
| matrixone-operator | `third/matrixone-operator` | root |
| gitops, deployment config | `third/gitops` | `aliyun/cloud-service/` |
| moi-gitops, helm chart | `third/moi-gitops` | `charts/moi-core/` |
| moi-op, IDC deploy | `third/moi-op` | root |
| cluster-controller | `third/cluster-controller` | root |
| scale-agent | `third/scale-agent` | root |
| frontend, moi-frontend | `third/moi-frontend` | `apps/` |
| ob-ops | `third/ob-ops` | root |
| ops, infrastructure | `third/ops` | root |

## Workflow

### Step 1: Fetch the Issue

```bash
gh issue view <NUMBER> --repo <OWNER/REPO> --json title,body,labels,state,comments
```

If the user provides a full URL like `https://github.com/owner/repo/issues/123`, extract the owner/repo and number from it.

Read all comments carefully — they often contain error messages, logs, timestamps, and environment references that are critical for diagnosis.

### Step 2: Identify What to Investigate

From the issue title, body, and comments, extract:

1. **Environment** — which env (dev/qa/prod/IDC)? This determines which KUBECONFIG to use.
2. **Service/Component** — which service is affected? Map it to the right submodule and k8s namespace.
3. **Symptoms** — error messages, logs snippets, timestamps, affected resources.
4. **Existing analysis** — what has already been investigated or ruled out by commenters.

Common namespace patterns:
- CP services: `mocloud` namespace (billing, instance, admin, auth, etc.)
- moi-core services: `moi-*` namespaces on unit clusters (moi-backend, moi-catalog, moi-mowl, etc.)
- unit-agent: `cos-system` namespace on unit clusters
- MO clusters: various namespaces on unit clusters (usually named after the cluster)
- IDC moi services: `moi-*` namespaces on `idc-unit`
- IDC mo-pl: `mo-pl` namespace on `idc-unit`

### Step 2b: Collect External Logs (Performance Issues)

Performance issues often reference logs in external locations (Gist, attachments, Grafana). Extract them early:

```bash
# If issue references a Gist URL
gh gist view <gist-id> --files                    # list files
gh gist view <gist-id> -f "<filename>" > /tmp/<filename>  # download each

# If logs are in k8s pods, extract and save locally
KUBECONFIG=~/.kube/<config> kubectl logs -n <namespace> <pod> --since=24h 2>&1 \
  | sed -n '/target file <file_id>/,/No pending file found/p' > /tmp/<file_id>.log
```

**For multi-service correlation**: download ALL relevant logs (job-consumer, llm-proxy, etc.) before starting analysis. Correlate by timestamp and request/file IDs.

### Step 3: Source Code Investigation

If in the `moi-core-handbooks` repo, ensure the relevant submodule is initialized:
```bash
git submodule update --init third/<name>
```

If in the `matrixflow` repo, source code is directly accessible.

Then search for relevant code based on the error messages or component mentioned in the issue:
- Grep for error strings, function names, or config keys
- Read the relevant handler/controller code to understand the expected behavior
- Check recent commits if the issue mentions a version or timeframe

Focus on understanding the root cause path — what code path produces the observed error.

#### Metric Code Tracing (Performance Issues)

When a Grafana metric shows unexpected values, **trace the metric to its recording point in code**:

1. **Find the metric name** in code: `grep -rn "<metric_name>"` across Python and Go
2. **Identify the recording mechanism**: decorator (`@track_function_latency_metrics`), context manager (`with self._track()`), or manual `histogram.observe()`
3. **Understand what's measured**: wall-clock of a function? cumulative? per-attempt vs including retries?
4. **Check histogram bucket boundaries** (e.g., `constant.py` `default_duration_bucket`) — are they appropriate for the actual value range?
5. **Verify Grafana query** — does it query the Prometheus metric (`function_duration_seconds`) or the PerformanceProfiler stage?

Common pitfall: The V2 pipeline has **two parallel metric systems**:
- `@track_function_latency_metrics(operation="...")` → Prometheus histogram (`function_duration_seconds`) → Grafana
- `with self._track("stage_name"):` → PerformanceProfiler (`StageMetrics`) → performance profile report
Both may use different names for the same operation.

### Step 4: Kubernetes Diagnostics

Only run k8s commands if the issue involves a running service or pod problem. Select the correct KUBECONFIG based on the environment identified in Step 2.

Run diagnostics progressively — start broad, then narrow down:

```bash
# Pod status
KUBECONFIG=~/.kube/<config> kubectl get pods -n <namespace> | grep <service>

# Detailed pod info (shows restart counts, conditions, events)
KUBECONFIG=~/.kube/<config> kubectl describe pod <pod-name> -n <namespace>

# Recent logs (last 200 lines, or since a timestamp)
KUBECONFIG=~/.kube/<config> kubectl logs <pod-name> -n <namespace> --tail=200
# If the pod has restarted, check previous container logs:
KUBECONFIG=~/.kube/<config> kubectl logs <pod-name> -n <namespace> --previous --tail=200

# Events in namespace (sorted by time)
KUBECONFIG=~/.kube/<config> kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -30

# Deployment/StatefulSet status
KUBECONFIG=~/.kube/<config> kubectl get deploy -n <namespace> | grep <service>
KUBECONFIG=~/.kube/<config> kubectl describe deploy <deploy-name> -n <namespace>

# Resource usage (if metrics available)
KUBECONFIG=~/.kube/<config> kubectl top pods -n <namespace> | grep <service>

# Node status (if node-level issue suspected)
KUBECONFIG=~/.kube/<config> kubectl get nodes -o wide
KUBECONFIG=~/.kube/<config> kubectl describe node <node-name>
```

Capture the key findings from each command — don't dump raw output into the comment. Summarize what matters.

If the issue involves Helm releases:
```bash
KUBECONFIG=~/.kube/<config> helm list -n <namespace> | grep <release>
KUBECONFIG=~/.kube/<config> helm history <release> -n <namespace> --max 5
```

### Step 5: Cross-reference with Existing Analysis

Check if similar issues have been analyzed before:
```bash
ls docs/analysis/ | grep -i <keyword>
```

Read relevant existing docs for context and to avoid duplicating investigation.

### Step 6: Synthesize and Post Comment

**For Performance issues, use the performance-specific template below. For other issue types, use the standard template.**

#### Standard Template (Crash/Error/Config)

```markdown
## 分析结果

### 现象
<Brief description of what's observed — error messages, symptoms>

### 环境信息
<Environment, cluster, namespace, pod names, image versions>

### 诊断发现
<Key findings from k8s diagnostics — pod status, restart counts, error logs, events>

### 代码分析
<If applicable: what the code does, why it fails, the specific code path>
<Include file paths as references, e.g., `moi-core/explore/engine/engine.go:142`>

### 根因
<Root cause analysis — the actual reason for the issue>

### 影响范围
<What's affected — which users, services, environments>

### 建议方案
<Recommended fix — immediate mitigation + long-term solution>
<Include specific commands for temporary fixes if applicable>

### 关联文档
<Links to related analysis docs in this repo, if any>
```

#### Performance Template (Slow/Timeout/Latency)

```markdown
## 深度分析：<metric/stage name> 性能瓶颈

> 基于 <list of log sources> 的关联分析

### 一、Metric 分析
<Why does the dashboard show X? Trace the metric recording code path.>
<Explain: what the metric records, histogram bucket issues, interpolation effects>

### 二、多日志关联分析
<Cross-service correlation: job-consumer ↔ llm-proxy ↔ upstream API>

#### 请求统计
| 指标 | 数值 |
...

#### VLM 调用详情
<Per-call breakdown: timestamp, operation, duration, tokens, tok/s, result>

#### 错误链分析
<Causal chain: e.g., high concurrency → throttling → timeout → retry → worse throttling>

### 三、根因
<Numbered root causes, ordered by impact>

### 四、优化方案
<Tiered: short-term (P0) / mid-term (P1) / long-term (P2) with expected impact>

### 附：处理时间线
<ASCII timeline showing stage durations and bottleneck markers>
```

Post the comment:
```bash
gh issue comment <NUMBER> --repo <OWNER/REPO> --body "$(cat <<'EOF'
<the analysis comment>
EOF
)"
```

## Parallel Agent Strategy

For complex performance issues involving multiple log sources, use the Agent tool to parallelize analysis:

```
# Launch 3 parallel agents for independent log analysis:
Agent("Analyze job-consumer DOCX log", prompt="Analyze /tmp/docx.log for: VLM calls, stage timings, timeout patterns...")
Agent("Analyze llm-proxy log", prompt="Analyze /tmp/llm-proxy.log for: request distribution, error classification, tok/s analysis...")
Agent("Analyze comparison log", prompt="Analyze /tmp/pdf.log and compare against DOCX processing...")
```

**When to parallelize:**
- Multiple independent log files to analyze (job-consumer + llm-proxy + comparison)
- Code search across different service directories
- K8s diagnostics on multiple clusters/namespaces

**When NOT to parallelize:**
- Sequential dependencies (need log findings before code search)
- Single-file analysis (overhead > benefit)

After all agents return, **synthesize** their findings yourself — don't delegate the cross-cutting analysis. The value is in connecting patterns across logs (e.g., DashScope 503 in llm-proxy correlating with timeout in job-consumer).

## User-Specified Analysis Focus

When the user provides specific questions (not just "analyze this issue"), structure your analysis around those questions explicitly:

1. Number and quote each user question
2. Dedicate a section of the comment to each question with a direct answer
3. Support each answer with evidence from logs/code/metrics
4. Don't bury the answers in a generic analysis structure

Example: If the user asks "是metric分桶不合理还是重试多统计了耗时", the comment should have a section titled exactly addressing that question, with a clear YES/NO + evidence.

## Important Rules

1. **Security**: Never include full API keys, passwords, or tokens in comments. Redact to first 8 chars + `...`.
2. **Accuracy**: Only state what you can verify. If you can't reach a cluster or a submodule isn't initialized, say so explicitly rather than guessing.
3. **Existing context**: Read all issue comments before investigating — someone may have already identified the problem or provided crucial clues.
4. **Don't over-diagnose**: If the issue is a simple question or feature request (not a bug/incident), say so briefly instead of running full diagnostics.
5. **Incremental posting**: For complex issues, consider posting an initial findings comment and updating as you learn more, rather than doing everything silently and posting one giant comment at the end.
6. **Link back**: If you create an analysis doc in `docs/issue/` or `docs/analysis/`, link to it from the issue comment using the full GitHub URL.
7. **Cross-repo awareness**: This skill may run in different repos (matrixflow vs moi-core-handbooks). Adapt paths accordingly — check for `third/` submodules vs direct source.
