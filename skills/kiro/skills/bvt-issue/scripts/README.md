# Background Task Scripts

## analyze-ci-logs.sh

Automated BVT failure analysis using a **gh-first tiered strategy**: prioritizes fast `gh api` calls for structured failure details before downloading heavy artifacts.

### Usage

```bash
./analyze-ci-logs.sh <run-id> <issue-number> [job-id]
./analyze-ci-logs.sh --reanalyze <issue-number>
```

### Analysis Tiers

| Tier | Method | Speed | What it provides |
|------|--------|-------|-----------------|
| **1** | `gh api` (annotations + jobs) | ~5s | Structured test failure messages, failed job/step names |
| **2** | `gh run view --log-failed` | ~30s | Raw failed step logs with error context |
| **3** | `gh run download` (artifacts) | ~2-5min | Service logs, pytest.log, test_results |

The comment is composed with Tier 1 data at the top (most valuable), followed by Tier 2 and 3 details.

### Required Permissions

```bash
gh auth refresh -s repo -s actions:read -s gist
```

### What It Does

1. **Tier 1** — Fetches run metadata, failed jobs/steps, and check-run annotations via `gh api`
2. **Tier 2** — Fetches failed step logs via `gh run view --log-failed`
3. **Tier 3** — Downloads `logs` and `bvt-runlog` artifacts, scans for errors
4. **Upload** — Creates a public Gist with all collected log files
5. **Comment** — Posts structured analysis to the issue (annotations first, then logs)

### Output

Comment structure:
- Run metadata (conclusion, branch, SHA)
- Full Logs link (Gist)
- Failed Jobs & Steps (Tier 1)
- Test Failure Annotations (Tier 1)
- CI Step Log Errors (Tier 2)
- Pytest Log Summary (Tier 3)
- Service Log Errors (Tier 3)

Comment body truncated to 60KB (GitHub limit). Temp files in `/tmp/bvt-analysis-<run-id>/` cleaned up after posting.
