---
name: log-perf-analyze
description: "Analyze MOI document-processing or service logs for performance bottlenecks, slow parsing, job-consumer latency, VLM/LLM latency, llm-proxy behavior, pipeline stage timing, L1 HTML generation, cross-page table merge, file_id/job_id investigations, Grafana metric anomalies, and cross-document comparisons in IDC/dev/qa/prod."
---

# Log Performance Analyze

Trace document-processing latency across job-consumer, llm-proxy, and upstream model calls.

## Key Rules

- Prefer evidence from full lifecycle logs, not isolated slow lines.
- Prometheus p95 can be misleading with sparse histogram buckets; inspect bucket boundaries before concluding.
- DashScope throughput degradation under concurrency is a common VLM timeout cause.
- L1 HTML generation and cross-page table merge are frequent dominant bottlenecks.
- Distinguish two metric systems: Prometheus decorators (`function_duration_seconds`) and `PerformanceProfiler` stage timing.
- Convert timestamps carefully: logs are often UTC; user reports are often CST.
- Strip ANSI color and redact secrets before publishing logs.

## Workflow

1. Identify `file_id`, `job_id`, time range, and environment from the user input or issue.
2. Locate the processing pod by searching job-consumer logs for the ID.
3. Extract complete job-consumer logs from processing start to completion/failure.
4. Collect llm-proxy logs for the same time window; map `remote_addr` to pod IPs when concurrency matters.
5. Parse stage timings: conversion, Paddle, MinerU, block creation, flowchart/table detection, L1 HTML, placeholder replacement, cross-page merge, image fragment merge, header/footer removal, title detection, content dispatch, writer.
6. Correlate model calls with timeouts, retries, token sizes, tok/s, 500 errors, provider throttling, and upstream latency.
7. When Grafana metrics are involved, trace metric code paths, recording scope, retry behavior, and histogram buckets before concluding.
8. For multiple samples, compare overlap windows, pipeline differences, VLM tok/s, timeout rates, and whether concurrency rather than file format explains the delta.
9. Produce a report with stage table, ASCII bottleneck visualization, VLM details, llm-proxy correlation, root cause, and P0/P1/P2 recommendations.
10. Save analysis under `docs/issue/` or `docs/analysis/` when appropriate; if requested, create or comment on a GitHub issue.

## Resources

- Read `references/pipeline-stages.md` for stage details.
- Read `references/metric-code-paths.md` for metrics and code-path mapping.
