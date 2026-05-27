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
2. LogSet readiness, available stores, StatefulSet status, image IDs, and recent shard errors.
3. DNSet readiness and replica status.
4. CNPool images and pod phase distribution.
5. ProxySet readiness and replica status.
6. Namespace events sorted by time when a component looks unhealthy.

## Output

Report status by component, concrete unhealthy pods/resources, and recommended next checks. If `--issue` is set, create an issue only with clear evidence.
