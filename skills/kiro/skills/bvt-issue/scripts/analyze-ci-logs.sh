#!/bin/bash
# BVT issue CI log analysis (gh-first strategy)
# Prioritizes gh API for structured failure details before downloading heavy artifacts.
#
# Usage:
#   ./analyze-ci-logs.sh <run-id> <issue-number> [job-id]
#   ./analyze-ci-logs.sh --reanalyze <issue-number>

set -e

REPO="matrixorigin/matrixflow"
TIMEOUT=1800

# --- Argument Parsing ---
if [[ "$1" == "--reanalyze" ]]; then
    ISSUE_NUMBER="$2"
    [[ -z "$ISSUE_NUMBER" ]] && { echo "Usage: $0 --reanalyze <issue-number>"; exit 1; }
    echo "Re-analyzing issue #$ISSUE_NUMBER..."
    ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json body -q '.body' 2>/dev/null || true)
    [[ -z "$ISSUE_BODY" ]] && { echo "Error: Failed to fetch issue #$ISSUE_NUMBER"; exit 1; }
    RUN_ID=$(echo "$ISSUE_BODY" | grep -oE 'actions/runs/([0-9]+)' | head -1 | grep -oE '[0-9]+$' || true)
    if [[ -z "$RUN_ID" ]]; then
        RUN_ID=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json comments -q '.comments[].body' 2>/dev/null \
            | grep -oE 'actions/runs/([0-9]+)' | head -1 | grep -oE '[0-9]+$' || true)
    fi
    if [[ -z "$RUN_ID" ]]; then
        gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "⚠️ Re-analysis failed: no GitHub Actions run URL found in issue body or comments."
        exit 1
    fi
    JOB_ID=$(echo "$ISSUE_BODY" | grep -oE 'actions/runs/[0-9]+/job/([0-9]+)' | head -1 | grep -oE '[0-9]+$' || true)
    echo "Found run ID: $RUN_ID${JOB_ID:+, job ID: $JOB_ID}"
else
    RUN_ID="$1"; ISSUE_NUMBER="$2"; JOB_ID="${3:-}"
    [[ -z "$RUN_ID" || -z "$ISSUE_NUMBER" ]] && { echo "Usage: $0 <run-id> <issue-number> [job-id]"; exit 1; }
fi

WORK_DIR="/tmp/bvt-analysis-${RUN_ID}"
mkdir -p "$WORK_DIR"

# Verify auth
gh auth status &>/dev/null || { echo "Error: gh not authenticated. Run: gh auth login"; exit 1; }

# ============================================================
# Tier 1: gh API — Structured Failure Details (fast)
# ============================================================
echo "=== Tier 1: Fetching structured failure details via gh API ==="

# 1a. Run metadata
RUN_META="$WORK_DIR/run-meta.json"
gh api "repos/$REPO/actions/runs/$RUN_ID" \
    --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch}' \
    > "$RUN_META" 2>/dev/null || echo '{}' > "$RUN_META"

CONCLUSION=$(jq -r '.conclusion // "unknown"' "$RUN_META")
HEAD_BRANCH=$(jq -r '.head_branch // "unknown"' "$RUN_META")
HEAD_SHA=$(jq -r '.head_sha // "unknown"' "$RUN_META")
echo "  Run: $CONCLUSION | Branch: $HEAD_BRANCH | SHA: $HEAD_SHA"

# 1b. Failed jobs with step details
FAILED_JOBS="$WORK_DIR/failed-jobs.txt"
gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
    --jq '.jobs[] | select(.conclusion=="failure") | "**\(.name)** (\(.started_at) → \(.completed_at))\n  URL: \(.html_url)\n  Failed steps: \([.steps[] | select(.conclusion=="failure") | .name] | join(", "))"' \
    > "$FAILED_JOBS" 2>/dev/null || true
echo "  Failed jobs: $(wc -l < "$FAILED_JOBS" | tr -d ' ') lines"

# 1c. Annotations from failed jobs (test failure messages)
ANNOTATIONS="$WORK_DIR/annotations.txt"
> "$ANNOTATIONS"
FAILED_JOB_IDS=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
    --jq '.jobs[] | select(.conclusion=="failure") | .id' 2>/dev/null || true)

for JID in $FAILED_JOB_IDS; do
    gh api "repos/$REPO/check-runs/${JID}/annotations" \
        --jq '.[] | "[\(.annotation_level)] \(.path // ""):\(.start_line // "") — \(.title // "")\n  \(.message // "" | split("\n") | first)"' \
        >> "$ANNOTATIONS" 2>/dev/null || true
done
ANNOTATION_COUNT=$(grep -c '^\[' "$ANNOTATIONS" 2>/dev/null || echo 0)
echo "  Annotations: $ANNOTATION_COUNT"

# ============================================================
# Tier 2: Failed Step Logs
# ============================================================
echo "=== Tier 2: Fetching failed step logs ==="
LOG_FILE="$WORK_DIR/ci-logs.txt"
ERROR_CONTEXT="$WORK_DIR/error-context.txt"

if [[ -n "$JOB_ID" ]]; then
    timeout $TIMEOUT gh run view "$RUN_ID" --repo "$REPO" --job "$JOB_ID" --log > "$LOG_FILE" 2>&1 || true
else
    timeout $TIMEOUT gh run view "$RUN_ID" --repo "$REPO" --log-failed > "$LOG_FILE" 2>&1 || true
fi

if [[ -s "$LOG_FILE" ]]; then
    grep -B 50 -A 50 -E "(FAILED|ERROR|AssertionError|Exception|Traceback)" "$LOG_FILE" \
        | head -200 > "$ERROR_CONTEXT" 2>/dev/null || tail -100 "$LOG_FILE" > "$ERROR_CONTEXT"
    echo "  CI logs: $(wc -l < "$LOG_FILE" | tr -d ' ') lines, error context: $(wc -l < "$ERROR_CONTEXT" | tr -d ' ') lines"
else
    > "$ERROR_CONTEXT"
    echo "  CI logs: empty or fetch failed"
fi

# ============================================================
# Tier 3: Artifact Download (heavy)
# ============================================================
echo "=== Tier 3: Downloading artifacts ==="
ARTIFACTS_DIR="$WORK_DIR/artifacts"
mkdir -p "$ARTIFACTS_DIR"

for ARTIFACT_NAME in "logs" "bvt-runlog"; do
    echo "  Downloading: $ARTIFACT_NAME ..."
    timeout $TIMEOUT gh run download "$RUN_ID" --repo "$REPO" --name "$ARTIFACT_NAME" \
        --dir "$ARTIFACTS_DIR/$ARTIFACT_NAME" 2>/dev/null || echo "  $ARTIFACT_NAME: not found or failed"
done

# Service log errors
SERVICE_LOG_SUMMARY="$WORK_DIR/service-log-summary.txt"
> "$SERVICE_LOG_SUMMARY"
if [[ -d "$ARTIFACTS_DIR/logs" ]]; then
    for LOG in "$ARTIFACTS_DIR/logs"/*.log; do
        [[ -f "$LOG" ]] || continue
        SVC_NAME=$(basename "$LOG" .log)
        ERRORS=$(grep -n -E "(ERROR|FATAL|panic|exception|Traceback)" "$LOG" | tail -20 2>/dev/null || true)
        if [[ -n "$ERRORS" ]]; then
            printf '### %s\n```\n%s\n```\n\n' "$SVC_NAME" "$ERRORS" >> "$SERVICE_LOG_SUMMARY"
        fi
    done
    # test_results
    if [[ -d "$ARTIFACTS_DIR/logs/test_results" ]]; then
        {
            echo '### test_results (generic_genai)'
            echo '```'
            find "$ARTIFACTS_DIR/logs/test_results" -type f \( -name "*.txt" -o -name "*.json" -o -name "*.log" \) \
                -exec sh -c 'echo "--- $(basename "$1") ---"; head -50 "$1"' _ {} \;
            echo '```'
            echo ""
        } >> "$SERVICE_LOG_SUMMARY" 2>/dev/null
    fi
fi

# Pytest log summary
PYTEST_LOG_SUMMARY="$WORK_DIR/pytest-log-summary.txt"
> "$PYTEST_LOG_SUMMARY"
if [[ -f "$ARTIFACTS_DIR/bvt-runlog/pytest.log" ]]; then
    {
        grep -E "(FAILED|ERROR|PASSED|short test summary)" "$ARTIFACTS_DIR/bvt-runlog/pytest.log" | tail -30
        echo "---"
        tail -50 "$ARTIFACTS_DIR/bvt-runlog/pytest.log"
    } > "$PYTEST_LOG_SUMMARY" 2>/dev/null
fi

# ============================================================
# Upload & Comment
# ============================================================
echo "=== Uploading logs to Gist ==="
GIST_FILES=()
for F in "$LOG_FILE" "$ERROR_CONTEXT" "$SERVICE_LOG_SUMMARY" "$PYTEST_LOG_SUMMARY" "$ANNOTATIONS"; do
    [[ -s "$F" ]] && GIST_FILES+=("$F")
done
if [[ -d "$ARTIFACTS_DIR/logs" ]]; then
    for F in "$ARTIFACTS_DIR/logs"/*.log; do [[ -f "$F" && -s "$F" ]] && GIST_FILES+=("$F"); done
fi
[[ -f "$ARTIFACTS_DIR/bvt-runlog/pytest.log" ]] && GIST_FILES+=("$ARTIFACTS_DIR/bvt-runlog/pytest.log")

GIST_URL=""
if [[ ${#GIST_FILES[@]} -gt 0 ]]; then
    GIST_URL=$(gh gist create --public --desc "BVT Issue #$ISSUE_NUMBER - CI logs for run $RUN_ID" "${GIST_FILES[@]}" 2>/dev/null || true)
    [[ -n "$GIST_URL" ]] && echo "  Gist: $GIST_URL" || echo "  Gist creation failed"
fi

echo "=== Posting analysis to issue #$ISSUE_NUMBER ==="

COMMENT_BODY="## CI Log Analysis

**Run**: https://github.com/$REPO/actions/runs/$RUN_ID
**Conclusion**: $CONCLUSION | **Branch**: $HEAD_BRANCH | **SHA**: $HEAD_SHA"

[[ -n "$GIST_URL" ]] && COMMENT_BODY+="
**Full Logs**: $GIST_URL"

# Tier 1: Failed jobs & annotations (most valuable)
if [[ -s "$FAILED_JOBS" ]]; then
    COMMENT_BODY+="

### Failed Jobs & Steps
$(head -c 10000 "$FAILED_JOBS")"
fi

if [[ -s "$ANNOTATIONS" ]]; then
    COMMENT_BODY+="

### Test Failure Annotations
\`\`\`
$(head -c 20000 "$ANNOTATIONS")
\`\`\`"
fi

# Tier 2: CI step log errors
if [[ -s "$ERROR_CONTEXT" ]]; then
    COMMENT_BODY+="

### CI Step Log Errors
\`\`\`
$(head -c 20000 "$ERROR_CONTEXT")
\`\`\`"
fi

# Tier 3: Pytest + service logs
if [[ -s "$PYTEST_LOG_SUMMARY" ]]; then
    COMMENT_BODY+="

### Pytest Log Summary
\`\`\`
$(head -c 10000 "$PYTEST_LOG_SUMMARY")
\`\`\`"
fi

if [[ -s "$SERVICE_LOG_SUMMARY" ]]; then
    COMMENT_BODY+="

### Service Log Errors
$(head -c 15000 "$SERVICE_LOG_SUMMARY")"
fi

# Truncate to GitHub limit
COMMENT_BODY=$(echo "$COMMENT_BODY" | head -c 60000)

gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$COMMENT_BODY"

# Cleanup
rm -rf "$WORK_DIR"
echo "✅ Analysis complete. Issue #$ISSUE_NUMBER updated."
