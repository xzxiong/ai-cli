# Metric Code Paths Reference

Quick lookup for tracing Grafana metrics back to source code.

## V2 Pipeline Metrics (Python, workflow_be)

### l1_html_generation (Grafana)

- **Prometheus**: `@track_function_latency_metrics(operation="l1_html_generation")`
- **Function**: `_generate_html_for_all_tables()` at `workflow_be/src/byoa/integrations/document_parser/v2/pipeline.py:1666`
- **What it measures**: Wall-clock of the entire function (ThreadPoolExecutor submit + wait for all futures)
- **Called from**: `pipeline.py:743` (Round 1, Paddle tables) and `pipeline.py:901` (Round 2, placeholder tables)
- **Each call is a separate Prometheus observation** — two rounds = two data points, not cumulative

### table_html_generation (PerformanceProfiler, NOT Grafana)

- **Profiler**: `with self._track("table_html_generation"):` at `pipeline.py:743, 901`
- **Same scope** as `l1_html_generation` above, but different metric system
- **PerformanceProfiler** defined at `performance.py:248`, tracks via `track_stage()` context manager
- **Stage name** registered in `PIPELINE_STAGES` frozenset at `performance.py:45`

### VLM Call per-table

- **Prometheus**: `@track_function_latency_metrics` on `call_vlm()` with `operation="vlm_call"`
- **task_name**: `"l1_html_generation"` (passed to VLM caller, used in logging)
- **Timeout**: `config.l1_html_generation_timeout` (default 120s, IDC override to 303s)
- **Retries**: `config.l1_html_generation_retries` (default 1)
- **Config file**: `workflow_be/src/byoa/integrations/document_parser/v2/config.py:107-112`

### cross_page_table_merge

- **Prometheus**: `@track_function_latency_metrics(operation="cross_page_table_merge")` on `merge()`
- **Key sub-operations**:
  - `_extract_structures_for_candidates()` — single VLM call, task_name=`cross_page_table_html_gen` at `cross_page_table_merger.py:906`
  - `_validate_candidates()` — per-pair VLM calls for matching
- **Timeout**: `self._vlm_timeout` (from config)

## Histogram Buckets

- **Definition**: `workflow_be/src/byoa/metrics/constant.py:6-26`
- **Used by**: `workflow_be/src/byoa/metrics/decorators.py:72` → `function_duration` Histogram
- **Buckets**: `[0.1, 0.5, 1, 2, 5, 10, 20, 30, 45, 60, 90, 120, 180, 300, 600, 1200, 1800, 2700, 3600]`
- **Known issue**: 300→600 gap causes p95 interpolation to overestimate for values ~303s

## Grafana Dashboard Registration (Go, catalog_service)

- **File**: `catalog_service/pkg/metrics/dashboard/dashboard_job_consumer.go:328`
- **Operations tracked**: `l1_html_generation`, `cross_page_table_merge`, `pipeline_process`, etc.
- **Note**: `table_html_generation` is NOT in this list — it's profiler-only

## llm-proxy Timeout Chain (Go)

```
Backend config (DB or YAML)
  → models.Backend.Timeout (types.go:468)
    → default 30s if not set (config.go:296)
      → qianwen adapter: http.Client{Timeout: config.Timeout} (qianwen.go:87)
        → DashScope API call with this timeout
```

- IDC typically sets backend timeout to 300s via DB dynamic config
- job-consumer has its own timeout at 303s (`l1_html_generation_future_timeout` + overhead)
- The two timeouts are independent: llm-proxy 300s HTTP timeout vs job-consumer 303s future timeout

## ThreadPoolExecutor Concurrency

- **L1 HTML Gen**: `max_workers` from `config.max_workers` or `PIPELINE_MAX_WORKERS` env (default 16)
- **Future timeout**: `config.l1_html_generation_future_timeout` (default 120s) at `pipeline.py:1872`
- All tables submitted concurrently → wall-clock = max(individual VLM calls)
- If any VLM call hits 303s timeout, the entire function reports ~303s
