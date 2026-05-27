---
name: issue-analyzer
description: "Analyze a GitHub issue end to end: fetch issue and comments, classify the problem, inspect source code or third/ submodules, run Kubernetes diagnostics with the right KUBECONFIG, and post a structured issue comment. Use for issue investigation, pod/service diagnosis, GitHub issue URLs, or requests to analyze and comment on an issue."
---

# Issue Analyzer

Investigate MOI/MatrixFlow issues with evidence from GitHub, code, and runtime diagnostics.

## Workflow

1. Fetch the issue and comments with `gh issue view`/`gh api`.
2. Classify the issue:
   - Crash/error: stack traces, panic, 5xx.
   - Performance: slow, timeout, p95/p99, latency; delegate to `log-perf-analyze` where appropriate.
   - Config/deploy: Helm, env, startup failures.
   - Feature/question: keep analysis brief.
3. Extract environment, service/component, symptoms, timestamps, and affected resources.
4. Locate related source code in the local repo or `third/` submodules.
5. Run Kubernetes diagnostics with the environment-specific kubeconfig.
6. Synthesize root cause, evidence, impact, and next actions.
7. Save analysis under the repo's issue-analysis docs when appropriate, then post a GitHub comment if requested or implied.

## Environment Hints

- dev: CP `~/.kube/ack-dev-control-plane`, DP `~/.kube/ack-unit-hz-new`
- qa: CP `~/.kube/ack-qa-control-plane`, DP `~/.kube/ack-unit-hz-qa`
- prod: CP `~/.kube/ack-prod-control-plane`, DP `~/.kube/ack-prod-unit-hz`
- IDC: DP `~/.kube/idc-unit`
