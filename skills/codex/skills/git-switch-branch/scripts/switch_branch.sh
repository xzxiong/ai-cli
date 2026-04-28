#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: bash scripts/switch_branch.sh <branch_name>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

target="$1"

if [[ -z "$target" ]]; then
  usage
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a Git repository." >&2
  exit 1
fi

remote_list="$(git remote)"
if [[ -n "$remote_list" ]]; then
  git fetch --all --prune --quiet >/dev/null 2>&1 || {
    echo "Warning: failed to fetch remotes; using local ref cache." >&2
  }
fi

mapfile -t local_branches < <(git for-each-ref --format='%(refname:short)' refs/heads)
mapfile -t remote_refs < <(git for-each-ref --format='%(refname:short)' refs/remotes | awk '!/\/HEAD$/')

find_exact_remote_matches() {
  local branch_name="$1"
  local ref short
  local matches=()
  for ref in "${remote_refs[@]}"; do
    short="${ref#*/}"
    if [[ "$short" == "$branch_name" ]]; then
      matches+=("$ref")
    fi
  done
  if [[ ${#matches[@]} -gt 0 ]]; then
    printf '%s\n' "${matches[@]}"
  fi
}

find_contains_matches() {
  local query_lc="$1"
  shift
  local item item_lc
  local matches=()
  for item in "$@"; do
    item_lc="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')"
    if [[ "$item_lc" == *"$query_lc"* ]]; then
      matches+=("$item")
    fi
  done
  if [[ ${#matches[@]} -gt 0 ]]; then
    printf '%s\n' "${matches[@]}"
  fi
}

for local_branch in "${local_branches[@]}"; do
  if [[ "$local_branch" == "$target" ]]; then
    git checkout "$local_branch"
    exit 0
  fi
done

mapfile -t exact_remote_matches < <(find_exact_remote_matches "$target")

if [[ ${#exact_remote_matches[@]} -eq 1 ]]; then
  git checkout -t "${exact_remote_matches[0]}"
  exit 0
fi

if [[ ${#exact_remote_matches[@]} -gt 1 ]]; then
  for remote_ref in "${exact_remote_matches[@]}"; do
    if [[ "$remote_ref" == "origin/$target" ]]; then
      git checkout -t "$remote_ref"
      exit 0
    fi
  done
  echo "Ambiguous exact remote branches for '$target':" >&2
  printf '  - %s\n' "${exact_remote_matches[@]}" >&2
  exit 1
fi

target_lc="$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')"
mapfile -t local_fuzzy_matches < <(find_contains_matches "$target_lc" "${local_branches[@]}")

if [[ ${#local_fuzzy_matches[@]} -eq 1 ]]; then
  git checkout "${local_fuzzy_matches[0]}"
  exit 0
fi

remote_short_names=()
for remote_ref in "${remote_refs[@]}"; do
  remote_short_names+=("${remote_ref#*/}")
done
mapfile -t remote_fuzzy_short_matches < <(find_contains_matches "$target_lc" "${remote_short_names[@]}")

if [[ ${#remote_fuzzy_short_matches[@]} -eq 1 ]]; then
  selected_short="${remote_fuzzy_short_matches[0]}"
  mapfile -t remote_short_exact_matches < <(find_exact_remote_matches "$selected_short")

  if [[ ${#remote_short_exact_matches[@]} -eq 1 ]]; then
    git checkout -t "${remote_short_exact_matches[0]}"
    exit 0
  fi

  for remote_ref in "${remote_short_exact_matches[@]}"; do
    if [[ "$remote_ref" == "origin/$selected_short" ]]; then
      git checkout -t "$remote_ref"
      exit 0
    fi
  done
fi

if [[ ${#local_fuzzy_matches[@]} -gt 1 || ${#remote_fuzzy_short_matches[@]} -gt 1 ]]; then
  echo "Ambiguous branch match for '$target'." >&2
  if [[ ${#local_fuzzy_matches[@]} -gt 0 ]]; then
    echo "Local candidates:" >&2
    printf '  - %s\n' "${local_fuzzy_matches[@]}" >&2
  fi
  if [[ ${#remote_fuzzy_short_matches[@]} -gt 0 ]]; then
    echo "Remote candidates:" >&2
    printf '  - %s\n' "${remote_fuzzy_short_matches[@]}" >&2
  fi
  exit 1
fi

echo "No branch matched '$target'." >&2
exit 1
