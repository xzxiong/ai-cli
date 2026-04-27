---
name: cluster-check
description: |
  Check MatrixOne Cloud cluster status on dev/qa/prod environments, with optional issue creation.
  
  Use this skill when:
  - The user says "check mo <env> <namespace>" (e.g., "check mo dev freetier-01")
  - The user says "check cluster" or "cluster status"
  - The user invokes `/cluster-check <namespace>` or `/cluster-check <env> <namespace>`
  - The user asks about LogSet, DNSet, CNPool, ProxySet status
  - The user wants to verify cluster health after operations
---

# Cluster Status Check Skill

## Purpose

Comprehensive health check of a MatrixOne cluster, covering all components: LogSet, DNSet, CNPool, ProxySet, and related infrastructure. Optionally create GitHub issues for detected problems.

## Trigger Patterns

| Pattern | Example | Description |
|---------|---------|-------------|
| `check mo <env> <ns>` | `check mo dev freetier-01` | 检查指定环境和集群 |
| `check mo <ns>` | `check mo freetier-01` | 检查 dev 环境（默认） |
| `check mo` | `check mo` | 检查 dev freetier-01（全默认） |
| `/cluster-check <env> <ns>` | `/cluster-check qa freetier-01` | 同上 |
| `/cluster-check <ns>` | `/cluster-check freetier-01` | 同上 |
| `check cluster ...` | `check cluster dev freetier-01` | 同上 |

**追加 `--issue` 或用户说"创建 issue"**：检查完成后自动创建 GitHub Issue。

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| env | `dev` | Environment: `dev`, `qa`, `prod` |
| namespace | `freetier-01` | K8s namespace of the cluster |
| --issue | false | 检查后创建 GitHub Issue（仅在发现异常时） |

## KUBECONFIG Mapping

| env | CP (Control Plane) | DP (Data Plane / Unit) |
|-----|-------------------|----------------------|
| dev | `~/.kube/ack-dev-control-plane` | `~/.kube/ack-unit-hz-new` |
| qa | `~/.kube/ack-qa-control-plane` | `~/.kube/ack-unit-hz-qa` |
| prod | `~/.kube/ack-prod-control-plane` | `~/.kube/ack-prod-unit-hz` |

## Process

### Step 1: Component Pods Overview

```bash
KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> \
  -l 'matrixorigin.io/component in (LogSet,DNSet,ProxySet)' \
  -o custom-columns="NAME:.metadata.name,COMPONENT:.metadata.labels.matrixorigin\.io/component,READY:.status.conditions[?(@.type==\"Ready\")].status,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName" \
  --no-headers
```

### Step 2: LogSet Detail

```bash
# CR status
KUBECONFIG=<dp-kubeconfig> kubectl get logset default -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} stores={range .status.availableStores[*]}{.podName}={.phase} {end}'

# StatefulSet
KUBECONFIG=<dp-kubeconfig> kubectl get statefulset.apps.kruise.io default-log -n <namespace> \
  -o jsonpath='replicas={.spec.replicas} ready={.status.readyReplicas} updated={.status.updatedReplicas} revision={.status.updateRevision} reserveOrdinals={.spec.reserveOrdinals}'

# Image consistency
KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> -l matrixorigin.io/component=LogSet \
  -o custom-columns="NAME:.metadata.name,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID" --no-headers

# Shard health (check for pending shards)
for pod in $(KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> -l matrixorigin.io/component=LogSet -o name --no-headers); do
  name=$(echo $pod | cut -d/ -f2)
  echo "=== $name ==="
  KUBECONFIG=<dp-kubeconfig> kubectl logs $name -n <namespace> --tail=3 --since=10s 2>&1 \
    | grep -E "(pending|reject|cannot|ERROR|failed)" || echo "OK"
done
```

### Step 3: DNSet Detail

```bash
KUBECONFIG=<dp-kubeconfig> kubectl get dnset default -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} replicas={.spec.replicas}'

KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> -l matrixorigin.io/component=DNSet \
  -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,IMAGE:.spec.containers[0].image" --no-headers
```

### Step 4: CNPool Detail

```bash
# Pool list with image
KUBECONFIG=<dp-kubeconfig> kubectl get cnpool -n <namespace> \
  -o custom-columns="NAME:.metadata.name,IMAGE:.spec.template.image" --no-headers

# Pod phases per pool
for pool in $(KUBECONFIG=<dp-kubeconfig> kubectl get cnpool -n <namespace> -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== $pool ==="
  KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> -l pool.matrixorigin.io/pool-name=$pool \
    -o custom-columns="PHASE:.metadata.labels.pool\.matrixorigin\.io/phase" --no-headers 2>/dev/null | sort | uniq -c
done
```

### Step 5: ProxySet Detail

```bash
KUBECONFIG=<dp-kubeconfig> kubectl get proxyset proxy -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} replicas={.spec.replicas}'

KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> -l matrixorigin.io/component=ProxySet \
  -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type==\"Ready\")].status,IMAGE:.spec.containers[0].image" --no-headers
```

### Step 6: CP Cluster CR

```bash
KUBECONFIG=<cp-kubeconfig> kubectl get cluster -n <namespace> \
  -o jsonpath='imageRepo={.spec.imageRepository} version={.spec.version} logReplicas={.spec.logSet.replicas} dnReplicas={.spec.dnSet.replicas} proxyReplicas={.spec.proxySet.replicas}'
```

### Step 7: Recent Warning Events

```bash
KUBECONFIG=<dp-kubeconfig> kubectl get events -n <namespace> \
  --sort-by='.lastTimestamp' --field-selector type=Warning 2>&1 | tail -15
```

### Step 8: Image Pull Errors (if any pod NotReady)

```bash
# Check for ImagePullBackOff / ErrImagePull
KUBECONFIG=<dp-kubeconfig> kubectl get pod -n <namespace> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.state.waiting.reason}{end}{"\n"}{end}' \
  | grep -E "(ImagePull|ErrImage)"
```

## Output Format

```markdown
## Cluster Status: <namespace> (<env>)

**Time**: <check-time>

### Overview
| Component | Pods | Ready | Image Tag | Status |
|-----------|------|-------|-----------|--------|
| LogSet    | 3    | 3/3   | v3.0.0-xxx | ✅ |
| DNSet     | 1    | 1/1   | v3.0.0-xxx | ✅ |
| ProxySet  | 2    | 2/2   | v3.0.0-xxx | ✅ |
| CNPool    | 8    | 8/8   | v3.0.0-xxx | ✅ |

### LogSet
- Stores: log-0=Up, log-1=Up, log-3=Up
- StatefulSet: replicas=3, reserveOrdinals=[2]
- Shard health: OK / ⚠️ shard X pending on <pod>

### CNPool
| Pool | Bound | Idle | Draining | Total |
|------|-------|------|----------|-------|
| s16c64g | 7 | 1 | 0 | 8 |

### Issues Found
- ⚠️ <issue-description>
- ✅ No issues detected
```

## Issue Creation (--issue)

When `--issue` is specified or user requests, and **issues are found**, create a GitHub Issue:

### Issue Target Repo Selection

通过 `third/` 下的 submodule 源码匹配异常关键词，自动选择最相关的 repo 提 issue。

**匹配流程**：
1. 从异常日志/错误中提取关键词（函数名、文件路径、组件名）
2. 在 `third/` 子目录中搜索匹配：`grep -rl "<keyword>" third/*/`
3. 根据匹配的 submodule 确定目标 repo

**Submodule → Repo 映射**：

| Submodule | Repo | 典型异常 |
|-----------|------|---------|
| `third/matrixone-operator` | `matrixorigin/matrixone-operator` | webhook 拒绝、LogSet/DNSet reconcile 异常、StatefulSet 更新卡住 |
| `third/cluster-controller` | `matrixorigin/cluster-controller` | CP webhook 改写 image、Cluster CR mutation 异常 |
| `third/unit-agent` | `matrixorigin/unit-agent` | DP CR 同步异常、imagePullSecrets 缺失、overlay 不生效 |
| `third/scale-agent` | `matrixorigin/scale-agent` | CNPool 扩缩容异常、节点调度问题 |
| `third/gitops` | `matrixorigin/gitops` | 部署配置问题、环境配置错误、镜像版本不一致 |
| `third/mocloud-services` | `matrixorigin/mocloud-services` | clusterservice/instanceservice 异常 |
| `third/ob-ops` | `matrixorigin/ob-ops` | 监控告警、Prometheus/VictoriaMetrics 异常 |

**搜索示例**：

```bash
# 异常日志包含 "logservice/store.go" → 搜索源码定位 repo
grep -rl "logservice/store.go" third/*/
# 匹配 third/mocloud-services/ 或 MO 内核 → matrixorigin/matrixone

# 异常日志包含 "webhook/cluster.go" → 搜索
grep -rl "webhook/cluster.go" third/*/
# 匹配 third/cluster-controller/ → matrixorigin/cluster-controller

# 异常日志包含 "syncLogSet" → 搜索
grep -rl "syncLogSet" third/*/
# 匹配 third/unit-agent/ → matrixorigin/unit-agent
```

**Fallback 规则**（当 `third/` 搜索无匹配时）：

| 异常类型 | 默认 Repo |
|---------|-----------|
| MO 内核日志（shard pending、Raft、HAKeeper、dragonboat） | `matrixorigin/matrixone` |
| K8s 基础设施（调度、镜像拉取、节点资源） | `matrixorigin/gitops` |
| 无法判断 | `matrixorigin/gitops`（运维兜底） |

### Issue Format

```bash
gh issue create --repo <target-repo> \
  --title "[<env>] <namespace>: <issue-summary>" \
  --label "kind/bug" \
  --assignee "xzxiong" \
  --body "<issue-body>"
```

**Issue body template**:

```markdown
## 环境

- **Env**: <env>
- **Namespace**: <namespace>
- **检查时间**: <timestamp>

## 异常概述

<summary-of-issues-found>

## 详细状态

<paste-check-output>

## 相关日志

<relevant-error-logs>

## 建议操作

<suggested-fix-steps>
```

**Rules**:
- 如果没有发现异常，不创建 issue，只输出 "✅ All healthy, no issue needed"
- 一次检查只创建一个 issue，多个异常合并到同一个 issue
- Issue title 简洁，不超过 70 字符
- 敏感信息（secret、token）脱敏处理

## Examples

```
User: check mo dev freetier-01

Kiro: ## Cluster Status: freetier-01 (dev)
      ...
      ### Issues Found
      - ✅ No issues detected
```

```
User: check mo qa freetier-01 --issue

Kiro: ## Cluster Status: freetier-01 (qa)
      ...
      ### Issues Found
      - ⚠️ LogSet log-2 shard 1 pending for 30min
      - ⚠️ Proxy pod ImagePullBackOff on node 10.3.93.177

      Created issue: https://github.com/matrixorigin/gitops/issues/4570
```

```
User: check mo

Kiro: ## Cluster Status: freetier-01 (dev)
      ...（使用全部默认值）
```
