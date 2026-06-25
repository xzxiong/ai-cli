---
name: cluster-check
description: Check MatrixOne Cloud cluster status in dev, qa, or prod Kubernetes environments, optionally creating a GitHub issue when anomalies are found. Use for `/cluster-check` or requests to inspect MO cluster health.
---

# Cluster Check

Check MatrixOne Cloud cluster status for an environment and namespace.

## Inputs

- `env`: `dev`, `qa`, or `prod`; default `dev`.
- `namespace`: default `freetier-01`.
- `--issue`: create an issue only if anomalies are found.

## Kubeconfig Mapping

- `dev`: DP `~/.kube/ack-unit-hz-new`, CP `~/.kube/ack-dev-control-plane`
- `qa`: DP `~/.kube/ack-unit-hz-qa`, CP `~/.kube/ack-qa-control-plane`
- `prod`: DP `~/.kube/ack-prod-unit-hz`, CP `~/.kube/ack-prod-control-plane`

## Checks

1. Pod overview for LogSet, DNSet, and ProxySet components.
2. LogSet readiness, available stores, StatefulSet status, image IDs, reserve ordinals, and recent shard errors.
3. DNSet readiness and replica status.
4. CNPool images and pod phase distribution (`Bound`, `Idle`, `Draining`, total).
5. ProxySet readiness and replica status.
6. CP Cluster CR image repository, version, LogSet/DNSet/ProxySet replica specs.
7. Namespace warning events sorted by time.
8. Image pull waiting states when any pod is not ready.

## Output

Report status by component, concrete unhealthy pods/resources, and recommended next checks. If `--issue` is set, create an issue only with clear evidence.

## Issue Routing

When `--issue` is set and anomalies exist, choose the repo from the likely component:

- `third/matrixone-operator` -> `matrixorigin/matrixone-operator` for webhook, reconcile, StatefulSet issues.
- `third/cluster-controller` -> `matrixorigin/cluster-controller` for CP webhook/mutation issues.
- `third/unit-agent` -> `matrixorigin/unit-agent` for DP CR sync or imagePullSecrets issues.
- `third/scale-agent` -> `matrixorigin/scale-agent` for CNPool scaling issues.
- `third/gitops` -> `matrixorigin/gitops` for deployment config or image version issues.
- fallback: MO kernel -> `matrixorigin/matrixone`; unclear K8s/deploy infra -> `matrixorigin/gitops`.

Do not create an issue when no anomaly is found. Merge multiple related anomalies into one issue, keep the title under about 70 characters, assign `xzxiong`, and redact secrets.
