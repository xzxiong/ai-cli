#!/usr/bin/env bash
# Add MatrixOrigin issues to the shared project and apply conservative initial triage.
set -euo pipefail

project_title="New MatrixOne Intelligence"
repo=""
issue_number=""
type_override="auto"
priority_override="auto"
iteration_selector="current"
item_value="开发实现"
labels_mode="auto"
dry_run=false

usage() {
  cat <<'EOF'
Usage: apply-matrixone-defaults.sh --repo OWNER/REPO --issue NUMBER [options]

Add a MatrixOrigin issue to the "New MatrixOne Intelligence" project, set its
Issue Type and Project fields, and apply conservative initial labels.

Options:
  --type auto|bug|feature|task  Override Type inference (default: auto)
  --priority auto|p0|p1|p2    Override Priority inference (default: auto/P2)
  --iteration current|TITLE    Use the active iteration or an exact title
  --labels auto|none|A,B        Automatic labels, no labels, or exact labels
  --dry-run                     Show intended changes without mutating GitHub
  -h, --help                    Show this help
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

while (($#)); do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --issue)
      issue_number="${2:-}"
      shift 2
      ;;
    --type)
      type_override="${2:-}"
      shift 2
      ;;
    --priority)
      priority_override="${2:-}"
      shift 2
      ;;
    --iteration)
      iteration_selector="${2:-}"
      shift 2
      ;;
    --labels)
      labels_mode="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

[[ -n "$repo" ]] || die "--repo is required"
[[ "$repo" == */* && "${repo#*/}" != */* ]] || die "--repo must be OWNER/REPO"
[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] || die "--issue must be a positive issue number"

owner="${repo%%/*}"
repository="${repo#*/}"
if [[ "$owner" != "matrixorigin" ]]; then
  log "Skipping MatrixOrigin defaults: $repo is not owned by matrixorigin."
  exit 0
fi

type_override="$(tr '[:upper:]' '[:lower:]' <<<"$type_override")"
case "$type_override" in
  auto|bug|feature|task) ;;
  *) die "--type must be auto, bug, feature, or task" ;;
esac
priority_override="$(tr '[:upper:]' '[:lower:]' <<<"$priority_override")"
case "$priority_override" in
  auto|p0|p1|p2) ;;
  *) die "--priority must be auto, p0, p1, or p2" ;;
esac
[[ -n "$iteration_selector" ]] || die "--iteration must be current or an iteration title"

require_command gh
require_command jq

issue_query='query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) {
      id
      title
      body
      labels(first: 100) { nodes { name } }
      projectItems(first: 100) { nodes { id project { id } } }
    }
  }
}'
issue_json="$(gh api graphql -f query="$issue_query" -f owner="$owner" -f repo="$repository" -F number="$issue_number")" || die "cannot read issue #$issue_number in $repo; verify the repository and issue number"
issue_node_id="$(jq -er '.data.repository.issue.id' <<<"$issue_json")"
issue_text="$(jq -r '[.data.repository.issue.title, .data.repository.issue.body, (.data.repository.issue.labels.nodes[]?.name)] | join("\n") | ascii_downcase' <<<"$issue_json")"

if [[ "$type_override" == "auto" ]]; then
  if [[ "$issue_text" == *"kind/bug"* || "$issue_text" =~ (bug|error|failed|failure|panic|crash|regression|异常|报错|失败|崩溃|回归) ]]; then
    issue_type="Bug"
  elif [[ "$issue_text" == *"kind/feature"* || "$issue_text" == *"kind/enhancement"* || "$issue_text" =~ (feature|enhancement|new[[:space:]]+capability|需求|功能|支持|增强) ]]; then
    issue_type="Feature"
  else
    issue_type="Task"
  fi
else
  issue_type="${type_override^}"
fi

if [[ "$priority_override" == "auto" ]]; then
  if [[ "$issue_text" == *"priority/p0"* || "$issue_text" == *"severity/s0"* || "$issue_text" =~ (critical|blocker|production[[:space:]]+outage|data[[:space:]]+loss|线上不可用|数据丢失) ]]; then
    priority="P0"
  elif [[ "$issue_text" == *"priority/p1"* || "$issue_text" == *"severity/s1"* || "$issue_text" =~ (urgent|high[[:space:]]+priority|严重) ]]; then
    priority="P1"
  else
    priority="P2"
  fi
else
  priority="${priority_override^}"
fi

issue_types_query='query($login: String!) {
  organization(login: $login) {
    issueTypes(first: 100) { nodes { id name isEnabled } }
  }
}'
issue_types_json="$(gh api graphql -f query="$issue_types_query" -f login="$owner")" || die "cannot read MatrixOrigin issue types; authorize with: gh auth refresh -s project"
issue_type_id="$(jq -er --arg name "$issue_type" '[.data.organization.issueTypes.nodes[] | select(.isEnabled and .name == $name)] | if length == 1 then .[0].id else empty end' <<<"$issue_types_json")" || die "MatrixOrigin has no enabled Issue Type named '$issue_type'"

project_query='query($login: String!) {
  organization(login: $login) {
    projectsV2(first: 100) {
      nodes {
        id
        title
        closed
        fields(first: 100) {
          nodes {
            __typename
            ... on ProjectV2SingleSelectField {
              id
              name
              options { id name }
            }
            ... on ProjectV2IterationField {
              id
              name
              configuration {
                iterations { id title startDate duration }
              }
            }
          }
        }
      }
    }
  }
}'
project_json="$(gh api graphql -f query="$project_query" -f login="$owner")" || die "cannot read MatrixOrigin projects; authorize with: gh auth refresh -s project"
project_count="$(jq --arg title "$project_title" '[.data.organization.projectsV2.nodes[] | select(.title == $title and .closed == false)] | length' <<<"$project_json")"
[[ "$project_count" == "1" ]] || die "expected one open project named '$project_title', found $project_count"
project_id="$(jq -er --arg title "$project_title" '.data.organization.projectsV2.nodes[] | select(.title == $title and .closed == false) | .id' <<<"$project_json")"

single_select_field() {
  local field_name="$1"
  jq -ce --arg title "$project_title" --arg field_name "$field_name" '
    [.data.organization.projectsV2.nodes[]
     | select(.title == $title and .closed == false)
     | .fields.nodes[]
     | select(((.name? // "") | ascii_downcase) == $field_name)]
    | if length == 1 then .[0] else empty end
  ' <<<"$project_json"
}

single_select_option_id() {
  local field_json="$1"
  shift
  local candidate option_id
  for candidate in "$@"; do
    option_id="$(jq -r --arg wanted "$candidate" '[.options[] | select(.name == $wanted)] | if length == 1 then .[0].id else empty end' <<<"$field_json")"
    if [[ -n "$option_id" ]]; then
      printf '%s\n' "$option_id"
      return 0
    fi
  done
  return 1
}

priority_field="$(single_select_field priority)" || die "project '$project_title' must expose exactly one single-select Priority field"
priority_field_id="$(jq -er '.id' <<<"$priority_field")"
case "$priority" in
  P0) priority_option_id="$(single_select_option_id "$priority_field" P0 'Priority 0' Critical)" || priority_option_id="" ;;
  P1) priority_option_id="$(single_select_option_id "$priority_field" P1 'Priority 1' High)" || priority_option_id="" ;;
  P2) priority_option_id="$(single_select_option_id "$priority_field" P2 'Priority 2' Medium)" || priority_option_id="" ;;
esac
[[ -n "${priority_option_id:-}" ]] || die "project '$project_title' Priority field has no option for '$priority'"

view_field="$(single_select_field '视角')" || die "project '$project_title' must expose exactly one single-select 视角 field"
view_field_id="$(jq -er '.id' <<<"$view_field")"
view_option_id="$(single_select_option_id "$view_field" "$item_value")" || die "project '$project_title' 视角 field has no '$item_value' option"

iteration_field="$(jq -ce --arg title "$project_title" '
  [.data.organization.projectsV2.nodes[]
   | select(.title == $title and .closed == false)
   | .fields.nodes[]
   | select(.__typename == "ProjectV2IterationField" and ((.name? // "") | ascii_downcase) == "iteration")]
  | if length == 1 then .[0] else empty end
' <<<"$project_json")" || die "project '$project_title' must expose exactly one Iteration field"
iteration_field_id="$(jq -er '.id' <<<"$iteration_field")"
if [[ "$iteration_selector" == "current" ]]; then
  today="$(date +%F)"
  iteration="$(jq -ce --arg today "$today" '
    [.configuration.iterations[]?
     | . as $iteration
     | select(
         ($iteration.startDate <= $today) and
         ($today < (($iteration.startDate | strptime("%Y-%m-%d") | mktime + ($iteration.duration * 86400) | strftime("%Y-%m-%d"))))
       )]
    | sort_by(.startDate)
    | if length == 1 then .[0] else empty end
  ' <<<"$iteration_field")" || die "project '$project_title' has no unique active iteration; pass --iteration '<exact title>'"
else
  iteration="$(jq -ce --arg title "$iteration_selector" '[.configuration.iterations[]? | select(.title == $title)] | if length == 1 then .[0] else empty end' <<<"$iteration_field")" || die "project '$project_title' has no unique iteration named '$iteration_selector'"
fi
iteration_id="$(jq -er '.id' <<<"$iteration")"
iteration_title="$(jq -er '.title' <<<"$iteration")"

project_item_id="$(jq -r --arg project "$project_id" '[.data.repository.issue.projectItems.nodes[] | select(.project.id == $project)] | .[0].id // empty' <<<"$issue_json")"
if [[ -z "$project_item_id" ]]; then
  if [[ "$dry_run" == true ]]; then
    log "Would add #$issue_number to project: $project_title"
    project_item_id="dry-run-item"
  else
    add_item_query='mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: {projectId: $project, contentId: $content}) { item { id } }
    }'
    project_item_id="$(gh api graphql -f query="$add_item_query" -f project="$project_id" -f content="$issue_node_id" --jq '.data.addProjectV2ItemById.item.id')"
    log "Added #$issue_number to project: $project_title"
  fi
else
  log "#${issue_number} is already in project: $project_title"
fi

set_single_select_value() {
  local field_id="$1"
  local option_id="$2"
  local field_name="$3"
  local option_name="$4"
  if [[ "$dry_run" == true ]]; then
    log "Would set $field_name: $option_name"
    return 0
  fi
  local set_single_select_query='mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $project
      itemId: $item
      fieldId: $field
      value: {singleSelectOptionId: $option}
    }) { projectV2Item { id } }
  }'
  gh api graphql -f query="$set_single_select_query" -f project="$project_id" -f item="$project_item_id" -f field="$field_id" -f option="$option_id" >/dev/null
  log "Set $field_name: $option_name"
}

set_iteration_value() {
  if [[ "$dry_run" == true ]]; then
    log "Would set Iteration: $iteration_title"
    return 0
  fi
  local set_iteration_query='mutation($project: ID!, $item: ID!, $field: ID!, $iteration: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $project
      itemId: $item
      fieldId: $field
      value: {iterationId: $iteration}
    }) { projectV2Item { id } }
  }'
  gh api graphql -f query="$set_iteration_query" -f project="$project_id" -f item="$project_item_id" -f field="$iteration_field_id" -f iteration="$iteration_id" >/dev/null
  log "Set Iteration: $iteration_title"
}

set_issue_type() {
  if [[ "$dry_run" == true ]]; then
    log "Would set Issue Type: $issue_type"
    return 0
  fi
  local set_issue_type_query='mutation($issue: ID!, $type: ID!) {
    updateIssue(input: {id: $issue, issueTypeId: $type}) { issue { id } }
  }'
  gh api graphql -f query="$set_issue_type_query" -f issue="$issue_node_id" -f type="$issue_type_id" >/dev/null
  log "Set Issue Type: $issue_type"
}

set_issue_type
set_single_select_value "$priority_field_id" "$priority_option_id" Priority "$priority"
set_single_select_value "$view_field_id" "$view_option_id" 视角 "$item_value"
set_iteration_value

declare -A available_labels=()
declare -A current_labels=()
while IFS= read -r label; do
  [[ -n "$label" ]] && available_labels["$label"]=1
done < <(gh api --paginate "repos/$repo/labels?per_page=100" --jq '.[].name')
while IFS= read -r label; do
  [[ -n "$label" ]] && current_labels["$label"]=1
done < <(jq -r '.data.repository.issue.labels.nodes[]?.name' <<<"$issue_json")

first_available_label() {
  local candidate
  for candidate in "$@"; do
    if [[ -n "${available_labels[$candidate]:-}" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

declare -a labels_to_add=()
add_label_once() {
  local candidate="$1"
  local existing
  [[ -n "$candidate" && -n "${available_labels[$candidate]:-}" && -z "${current_labels[$candidate]:-}" ]] || return 0
  for existing in "${labels_to_add[@]}"; do
    [[ "$existing" == "$candidate" ]] && return 0
  done
  labels_to_add+=("$candidate")
}

if [[ "$labels_mode" == "auto" ]]; then
  case "$issue_type" in
    Bug)
      add_label_once "$(first_available_label kind/bug kind/bug-mo kind/bug-moi || true)"
      ;;
    Feature)
      add_label_once "$(first_available_label kind/feature kind/feature-mo kind/feature-moi kind/enhancement kind/tech-request || true)"
      ;;
    Task)
      if [[ "$issue_text" =~ (documentation|document|文档) ]]; then
        add_label_once "$(first_available_label kind/documentation kind/doc || true)"
      elif [[ "$issue_text" =~ (refactor|重构) ]]; then
        add_label_once "$(first_available_label kind/refactor kind/refactoring || true)"
      elif [[ "$issue_text" =~ (test|ci|bvt|测试) ]]; then
        add_label_once "$(first_available_label kind/test-ci kind/test_request || true)"
      fi
      ;;
  esac
  if [[ "$issue_text" =~ (perf|performance|latency|throughput|性能|延迟|吞吐) ]]; then
    add_label_once "$(first_available_label area/performance || true)"
  elif [[ "$issue_text" =~ (optimizer|优化器) ]]; then
    add_label_once "$(first_available_label area/optimizer || true)"
  elif [[ "$issue_text" =~ (storage|存储) ]]; then
    add_label_once "$(first_available_label area/storage || true)"
  elif [[ "$issue_text" =~ (frontend|ui|前端) ]]; then
    add_label_once "$(first_available_label area/frontend || true)"
  fi
  add_label_once "$(first_available_label needs-triage || true)"
elif [[ "$labels_mode" != "none" ]]; then
  IFS=',' read -r -a requested_labels <<<"$labels_mode"
  for label in "${requested_labels[@]}"; do
    if [[ -z "${available_labels[$label]:-}" ]]; then
      log "Requested label is unavailable in $repo: $label"
    else
      add_label_once "$label"
    fi
  done
fi

if ((${#labels_to_add[@]} == 0)); then
  log "No initial labels to add"
elif [[ "$dry_run" == true ]]; then
  log "Would add labels: ${labels_to_add[*]}"
else
  for label in "${labels_to_add[@]}"; do
    gh issue edit "$issue_number" --repo "$repo" --add-label "$label" >/dev/null
  done
  log "Added labels: ${labels_to_add[*]}"
fi

printf 'Project: %s\nIssue Type: %s\nPriority: %s\nIteration: %s\n视角: %s\nLabels: %s\n' \
  "$project_title" "$issue_type" "$priority" "$iteration_title" "$item_value" "${labels_to_add[*]:-none}"
