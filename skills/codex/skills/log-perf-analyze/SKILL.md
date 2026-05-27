---
name: log-perf-analyze
description: Analyze MOI document-processing or service logs for performance bottlenecks, slow parsing, job-consumer latency, VLM/LLM latency, llm-proxy behavior, pipeline stage timing, L1 HTML generation, cross-page table merge, or file_id/job_id investigations. Use for `/log-perf-analyze` and performance issues in IDC/dev/qa/prod.
---

# Log Performance Analyze

Trace document-processing latency across job-consumer, llm-proxy, and upstream model calls.

## Key Rules

- Prefer evidence from full lifecycle logs, not isolated slow lines.
- Prometheus p95 can be misleading with sparse histogram buckets; inspect bucket boundaries before concluding.
- DashScope throughput degradation under concurrency is a common VLM timeout cause.
- L1 HTML generation and cross-page table merge are frequent dominant bottlenecks.

## Workflow

1. Identify `file_id`, `job_id`, time range, and environment from the user input or issue.
2. Locate the processing pod and collect job-consumer logs; collect llm-proxy logs for VLM/LLM calls.
3. Extract complete logs from processing start to completion/failure.
4. Parse stage timings: conversion, Paddle, MinerU, table detection, L1 HTML, cross-page merge, title detection, dispatch, writer.
5. Correlate model calls with timeouts, retries, token sizes, and upstream provider latency.
6. Compare metric systems where relevant: Prometheus decorators vs `PerformanceProfiler`.
7. Produce a report with top bottlenecks, timeline, root cause, and concrete optimization recommendations.
8. If requested, create or comment on a GitHub issue with the analysis.

## Resources

- Read `references/pipeline-stages.md` for stage details.
- Read `references/metric-code-paths.md` for metrics and code-path mapping.
