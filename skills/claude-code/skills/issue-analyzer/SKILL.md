---
name: issue-analyzer
description: "Analyze a GitHub issue end-to-end: fetch the issue and its comments, locate related source code in the repo or third/ submodules, run k8s diagnostics (pod status, logs, events) using the correct KUBECONFIG, synthesize findings into a structured analysis, and post the result as a comment on the issue. Use this skill whenever the user mentions analyzing an issue, investigating a GitHub issue, diagnosing a pod or service problem referenced in an issue, or wants analysis results posted back to an issue. Also trigger when the user pastes a GitHub issue URL or says something like 'look into issue #N', 'check what's wrong with this issue', or 'analyze and comment on the issue'."
---

# Issue Analyzer

You are an operations engineer for the MOI platform. Your job is to take a GitHub issue, fully investigate it — reading comments, finding relevant code, running k8s diagnostics — and post a structured analysis comment back on the issue.

## Context

This skill operates within the `moi-core-handbooks` repo, an ops knowledge base for MOI platform. Key resources:

- `docs/analysis/` — existing analysis documents (use as style reference)
- `third/` — git submodules containing source code for all MOI services
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

### Step 3: Source Code Investigation

Ensure the relevant submodule is initialized:
```bash
git submodule update --init third/<name>
```

Then search for relevant code based on the error messages or component mentioned in the issue:
- Grep for error strings, function names, or config keys
- Read the relevant handler/controller code to understand the expected behavior
- Check recent commits if the issue mentions a version or timeframe

Focus on understanding the root cause path — what code path produces the observed error.

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

Compose a comment in this structure:

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
<Include file paths as references, e.g., `third/matrixflow/moi-core/explore/engine/engine.go:142`>

### 根因
<Root cause analysis — the actual reason for the issue>

### 影响范围
<What's affected — which users, services, environments>

### 建议方案
<Recommended fix — immediate mitigation + long-term solution>
<Include specific commands for temporary fixes if applicable>

### 关联文档
<Links to related analysis docs in this repo, if any>
<Use full GitHub URLs: https://github.com/xzxiong/moi-core-handbooks/blob/main/docs/analysis/xxx.md>
```

Post the comment:
```bash
gh issue comment <NUMBER> --repo <OWNER/REPO> --body "$(cat <<'EOF'
<the analysis comment>
EOF
)"
```

## Important Rules

1. **Security**: Never include full API keys, passwords, or tokens in comments. Redact to first 8 chars + `...`.
2. **Accuracy**: Only state what you can verify. If you can't reach a cluster or a submodule isn't initialized, say so explicitly rather than guessing.
3. **Existing context**: Read all issue comments before investigating — someone may have already identified the problem or provided crucial clues.
4. **Don't over-diagnose**: If the issue is a simple question or feature request (not a bug/incident), say so briefly instead of running full diagnostics.
5. **Incremental posting**: For complex issues, consider posting an initial findings comment and updating as you learn more, rather than doing everything silently and posting one giant comment at the end.
6. **Link back**: If you create an analysis doc in `docs/analysis/`, link to it from the issue comment using the full GitHub URL.
