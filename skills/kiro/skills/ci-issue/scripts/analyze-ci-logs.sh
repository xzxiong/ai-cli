#!/bin/bash
# CI issue analysis script (artifact-first for moi-core)
#
# Usage: ./analyze-ci-logs.sh <run-id> <issue-number> [job-id]

set -e

REPO="matrixorigin/matrixflow"
TIMEOUT=1800

RUN_ID="$1"; ISSUE_NUMBER="$2"; JOB_ID="${3:-}"
[[ -z "$RUN_ID" || -z "$ISSUE_NUMBER" ]] && { echo "Usage: $0 <run-id> <issue-number> [job-id]"; exit 1; }

WORK_DIR="/tmp/ci-issue-${RUN_ID}"
mkdir -p "$WORK_DIR"

gh auth status &>/dev/null || { echo "Error: gh not authenticated"; exit 1; }

# ============================================================
# Tier 1: gh API
# ============================================================
echo "=== Tier 1: gh API ==="

RUN_META="$WORK_DIR/run-meta.json"
gh api "repos/$REPO/actions/runs/$RUN_ID" \
    --jq '{conclusion, run_started_at, updated_at, head_sha: .head_sha[:8], head_branch, name, display_title, event}' \
    > "$RUN_META" 2>/dev/null || echo '{}' > "$RUN_META"

CONCLUSION=$(jq -r '.conclusion // "unknown"' "$RUN_META")
HEAD_BRANCH=$(jq -r '.head_branch // "unknown"' "$RUN_META")
HEAD_SHA=$(jq -r '.head_sha // "unknown"' "$RUN_META")
WORKFLOW_NAME=$(jq -r '.name // "unknown"' "$RUN_META")
echo "  $WORKFLOW_NAME: $CONCLUSION | $HEAD_BRANCH | $HEAD_SHA"

FAILED_JOBS="$WORK_DIR/failed-jobs.txt"
gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
    --jq '.jobs[] | select(.conclusion=="failure") | "**\(.name)**\n  URL: \(.html_url)\n  Failed steps: \([.steps[] | select(.conclusion=="failure") | .name] | join(", "))"' \
    > "$FAILED_JOBS" 2>/dev/null || true

ANNOTATIONS="$WORK_DIR/annotations.txt"
> "$ANNOTATIONS"
FAILED_JOB_IDS=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --paginate \
    --jq '.jobs[] | select(.conclusion=="failure") | .id' 2>/dev/null || true)

for JID in $FAILED_JOB_IDS; do
    gh api "repos/$REPO/check-runs/${JID}/annotations" \
        --jq '.[] | select(.annotation_level=="failure") | "[\(.annotation_level)] \(.path // ""):\(.start_line // "") — \(.title // "")\n  \(.message // "" | split("\n") | first)"' \
        >> "$ANNOTATIONS" 2>/dev/null || true
done
echo "  Annotations: $(grep -c '^\[' "$ANNOTATIONS" 2>/dev/null || echo 0)"

# ============================================================
# Tier 2: Artifact Download (primary for moi-core)
# ============================================================
echo "=== Tier 2: Downloading artifacts ==="
ARTIFACTS_DIR="$WORK_DIR/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# Try moi-core-ci-artifacts first, then any available
timeout $TIMEOUT gh run download "$RUN_ID" --repo "$REPO" --name moi-core-ci-artifacts \
    --dir "$ARTIFACTS_DIR" 2>/dev/null || {
    echo "  moi-core-ci-artifacts not found, trying all artifacts..."
    ARTIFACT_NAMES=$(gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts" --jq '.artifacts[].name' 2>/dev/null || true)
    for NAME in $ARTIFACT_NAMES; do
        timeout $TIMEOUT gh run download "$RUN_ID" --repo "$REPO" --name "$NAME" \
            --dir "$ARTIFACTS_DIR/$NAME" 2>/dev/null || true
    done
}

# Analyze moi-core log files
STAGE_SUMMARY="$WORK_DIR/stage-summary.txt"
> "$STAGE_SUMMARY"

EXIT_CODE=""
[[ -f "$ARTIFACTS_DIR/logs/ci-exit-code" ]] && EXIT_CODE=$(cat "$ARTIFACTS_DIR/logs/ci-exit-code")
echo "  ci-exit-code: ${EXIT_CODE:-not found}"

for LOG_NAME in ci-test.log test-python-sdk.log test.log; do
    LOG_PATH="$ARTIFACTS_DIR/logs/$LOG_NAME"
    [[ -f "$LOG_PATH" ]] || continue
    ERRORS=$(grep -n -E "(FAIL|ERROR|undefined|cannot use|has no field|panic|Traceback|exit status|不一致)" "$LOG_PATH" | tail -30 2>/dev/null || true)
    if [[ -n "$ERRORS" ]]; then
        printf '#### %s\n```\n%s\n```\n\n' "$LOG_NAME" "$ERRORS" >> "$STAGE_SUMMARY"
    fi
done

# ============================================================
# Tier 3: Fallback — gh run view --log-failed
# ============================================================
LOG_FILE="$WORK_DIR/ci-logs.txt"
ERROR_CONTEXT="$WORK_DIR/error-context.txt"
> "$ERROR_CONTEXT"

if [[ ! -s "$STAGE_SUMMARY" ]]; then
    echo "=== Tier 3: Fallback log fetch ==="
    if [[ -n "$JOB_ID" ]]; then
        timeout $TIMEOUT gh run view "$RUN_ID" --repo "$REPO" --job "$JOB_ID" --log > "$LOG_FILE" 2>&1 || true
    else
        timeout $TIMEOUT gh run view "$RUN_ID" --repo "$REPO" --log-failed > "$LOG_FILE" 2>&1 || true
    fi
    [[ -s "$LOG_FILE" ]] && grep -B 20 -A 10 -E "(FAIL|ERROR|undefined|panic|Traceback)" "$LOG_FILE" \
        | head -200 > "$ERROR_CONTEXT" 2>/dev/null || true
fi

# ============================================================
# Upload & Comment
# ============================================================
echo "=== Uploading to Gist ==="
GIST_FILES=()
for F in "$ANNOTATIONS" "$STAGE_SUMMARY" "$ERROR_CONTEXT"; do
    [[ -s "$F" ]] && GIST_FILES+=("$F")
done
for F in "$ARTIFACTS_DIR/logs"/*.log; do
    [[ -f "$F" && -s "$F" ]] && GIST_FILES+=("$F")
done

GIST_URL=""
if [[ ${#GIST_FILES[@]} -gt 0 ]]; then
    GIST_URL=$(gh gist create --public --desc "CI Issue #$ISSUE_NUMBER - $WORKFLOW_NAME run $RUN_ID" "${GIST_FILES[@]}" 2>/dev/null || true)
    echo "  Gist: ${GIST_URL:-failed}"
fi

echo "=== Posting analysis ==="

COMMENT_BODY="## CI Log Analysis

**Run**: https://github.com/$REPO/actions/runs/$RUN_ID
**Workflow**: $WORKFLOW_NAME
**Conclusion**: $CONCLUSION | **Branch**: $HEAD_BRANCH | **SHA**: $HEAD_SHA"

[[ -n "$GIST_URL" ]] && COMMENT_BODY+="
**Full Logs**: $GIST_URL"

[[ -s "$FAILED_JOBS" ]] && COMMENT_BODY+="

### Failed Jobs & Steps
$(head -c 5000 "$FAILED_JOBS")"

[[ -s "$ANNOTATIONS" ]] && COMMENT_BODY+="

### Failure Annotations
\`\`\`
$(head -c 15000 "$ANNOTATIONS")
\`\`\`"

[[ -s "$STAGE_SUMMARY" ]] && COMMENT_BODY+="

### Stage Errors
$(head -c 30000 "$STAGE_SUMMARY")"

[[ -s "$ERROR_CONTEXT" ]] && COMMENT_BODY+="

### CI Log Errors
\`\`\`
$(head -c 15000 "$ERROR_CONTEXT")
\`\`\`"

COMMENT_BODY=$(echo "$COMMENT_BODY" | head -c 60000)
gh issue comment "$ISSUE_NUMBER" --repo "$REPO" --body "$COMMENT_BODY"

rm -rf "$WORK_DIR"
echo "✅ Analysis complete. Issue #$ISSUE_NUMBER updated."
