Check MatrixOne Cloud cluster status on dev/qa/prod environments, with optional issue creation.

Input: $ARGUMENTS (格式: [env] [namespace] [--issue])

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| env | `dev` | Environment: `dev`, `qa`, `prod` |
| namespace | `freetier-01` | K8s namespace |
| --issue | false | 检查后创建 GitHub Issue（仅在发现异常时） |

## KUBECONFIG Mapping

| env | CP (Control Plane) | DP (Data Plane) |
|-----|-------------------|-----------------|
| dev | `~/.kube/ack-dev-control-plane` | `~/.kube/ack-unit-hz-new` |
| qa | `~/.kube/ack-qa-control-plane` | `~/.kube/ack-unit-hz-qa` |
| prod | `~/.kube/ack-prod-control-plane` | `~/.kube/ack-prod-unit-hz` |

## 流程

### 1. Component Pods Overview
```bash
KUBECONFIG=<dp> kubectl get pod -n <namespace> \
  -l 'matrixorigin.io/component in (LogSet,DNSet,ProxySet)' \
  -o custom-columns="NAME:.metadata.name,COMPONENT:.metadata.labels.matrixorigin\.io/component,READY:.status.conditions[?(@.type==\"Ready\")].status,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName" --no-headers
```

### 2. LogSet Detail
```bash
KUBECONFIG=<dp> kubectl get logset default -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} stores={range .status.availableStores[*]}{.podName}={.phase} {end}'

KUBECONFIG=<dp> kubectl get statefulset.apps.kruise.io default-log -n <namespace> \
  -o jsonpath='replicas={.spec.replicas} ready={.status.readyReplicas} updated={.status.updatedReplicas} revision={.status.updateRevision} reserveOrdinals={.spec.reserveOrdinals}'

KUBECONFIG=<dp> kubectl get pod -n <namespace> -l matrixorigin.io/component=LogSet \
  -o custom-columns="NAME:.metadata.name,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID" --no-headers

# Shard health
for pod in $(KUBECONFIG=<dp> kubectl get pod -n <namespace> -l matrixorigin.io/component=LogSet -o name --no-headers); do
  name=$(echo $pod | cut -d/ -f2)
  KUBECONFIG=<dp> kubectl logs $name -n <namespace> --tail=3 --since=10s 2>&1 \
    | grep -E "(pending|reject|cannot|ERROR|failed)" || echo "OK"
done
```

### 3. DNSet Detail
```bash
KUBECONFIG=<dp> kubectl get dnset default -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} replicas={.spec.replicas}'
```

### 4. CNPool Detail
```bash
KUBECONFIG=<dp> kubectl get cnpool -n <namespace> \
  -o custom-columns="NAME:.metadata.name,IMAGE:.spec.template.image" --no-headers

for pool in $(KUBECONFIG=<dp> kubectl get cnpool -n <namespace> -o jsonpath='{.items[*].metadata.name}'); do
  KUBECONFIG=<dp> kubectl get pod -n <namespace> -l pool.matrixorigin.io/pool-name=$pool \
    -o custom-columns="PHASE:.metadata.labels.pool\.matrixorigin\.io/phase" --no-headers 2>/dev/null | sort | uniq -c
done
```

### 5. ProxySet Detail
```bash
KUBECONFIG=<dp> kubectl get proxyset proxy -n <namespace> \
  -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} replicas={.spec.replicas}'
```

### 6. CP Cluster CR
```bash
KUBECONFIG=<cp> kubectl get cluster -n <namespace> \
  -o jsonpath='imageRepo={.spec.imageRepository} version={.spec.version} logReplicas={.spec.logSet.replicas} dnReplicas={.spec.dnSet.replicas} proxyReplicas={.spec.proxySet.replicas}'
```

### 7. Recent Warning Events
```bash
KUBECONFIG=<dp> kubectl get events -n <namespace> --sort-by='.lastTimestamp' --field-selector type=Warning 2>&1 | tail -15
```

### 8. Image Pull Errors (if any pod NotReady)
```bash
KUBECONFIG=<dp> kubectl get pod -n <namespace> \
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

### LogSet
- Stores: log-0=Up, log-1=Up, log-3=Up
- StatefulSet: replicas=3, reserveOrdinals=[2]

### CNPool
| Pool | Bound | Idle | Draining | Total |
|------|-------|------|----------|-------|

### Issues Found
- ⚠️ / ✅ No issues detected
```

## Issue Creation (--issue)

When `--issue` is specified and issues are found:

**Submodule → Repo 映射**（通过 `grep -rl "<keyword>" third/*/` 搜索匹配）:

| Submodule | Repo | 典型异常 |
|-----------|------|---------|
| `third/matrixone-operator` | `matrixorigin/matrixone-operator` | webhook/reconcile/StatefulSet |
| `third/cluster-controller` | `matrixorigin/cluster-controller` | CP webhook/mutation |
| `third/unit-agent` | `matrixorigin/unit-agent` | DP CR 同步/imagePullSecrets |
| `third/scale-agent` | `matrixorigin/scale-agent` | CNPool 扩缩容 |
| `third/gitops` | `matrixorigin/gitops` | 部署配置/镜像版本 |

**Fallback**: MO 内核 → `matrixorigin/matrixone`; K8s 基础设施/无法判断 → `matrixorigin/gitops`

```bash
gh issue create --repo <target-repo> \
  --title "[<env>] <namespace>: <issue-summary>" \
  --label "kind/bug" --assignee "xzxiong" --body "<body>"
```

Rules: 无异常不创建; 多个异常合并一个 issue; title ≤70 字符; 敏感信息脱敏。
