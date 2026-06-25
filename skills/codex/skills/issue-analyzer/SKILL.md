---
name: issue-analyzer
description: "Analyze a GitHub issue end to end: fetch issue and comments, classify the problem, inspect source code or third/ submodules, collect external logs, run Kubernetes diagnostics with the right KUBECONFIG, synthesize root cause, and post a structured issue comment. Use for issue investigation, pod/service diagnosis, GitHub issue URLs, performance issues, config/deploy failures, or requests to analyze and comment on an issue."
---

# Issue Analyzer

Investigate MOI/MatrixFlow issues with evidence from GitHub, code, logs, and runtime diagnostics.

## Classification

- Crash/error: stack traces, panic, 5xx, failed jobs.
- Performance: slow, timeout, p95/p99, latency, document parsing bottlenecks. Use `log-perf-analyze` or its workflow inline.
- Config/deploy: Helm, env, startup, image, secret, or rollout failures.
- Feature/question: answer briefly; avoid unnecessary cluster work.

## Workflow

1. Fetch the issue and comments with `gh issue view`/`gh api`.
2. Extract environment, service/component, symptoms, timestamps, IDs, affected resources, and what commenters already tried.
3. Map the service to source code:
   - `matrixflow` / `moi-core`: `third/matrixflow` or current repo.
   - `mocloud`, billing, instance, auth, admin: `third/mocloud-services`.
   - deployment/config: `third/gitops`, `third/moi-gitops`, `third/moi-op`, `third/ops`, `third/ob-ops`.
   - frontend: `third/moi-frontend`.
4. Collect external logs early when referenced: Gist, attachments, pod logs, llm-proxy logs, file_id/job_id traces.
5. Locate code paths by error strings, metric names, config keys, handlers, or job IDs. For performance metrics, trace the metric recording point and bucket boundaries before interpreting Grafana.
6. Run Kubernetes diagnostics only when runtime state matters, using the environment-specific kubeconfig. Start broad, then narrow: pods, deploy/statefulset, logs, previous logs, events, helm history, resource usage.
7. Cross-reference existing docs under `docs/analysis/` or `docs/issue/` when present.
8. Synthesize root cause, evidence, impact, mitigation, and long-term fix.
9. Save analysis under the repo's issue-analysis docs when appropriate, then post a GitHub comment if requested or implied.

## Environment Hints

- dev: CP `~/.kube/ack-dev-control-plane`, DP `~/.kube/ack-unit-hz-new`
- qa: CP `~/.kube/ack-qa-control-plane`, DP `~/.kube/ack-unit-hz-qa`
- prod: CP `~/.kube/ack-prod-control-plane`, DP `~/.kube/ack-prod-unit-hz`
- IDC: DP `~/.kube/idc-unit`

## Comment Shape

Use Chinese unless the issue is clearly English-only:

- 现象
- 环境信息
- 诊断发现
- 代码分析
- 根因
- 影响范围
- 建议方案
- 关联文档/日志
