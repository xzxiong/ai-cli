---
name: git-switch-branch
description: Resolve and switch Git branches from commands like "switch to [branch] {branch_name}" by finding the best local or remote branch match, then running checkout. Use when the user asks to switch branches in English or Chinese, such as "switch to [branch] ...", "switch branch to ...", "切到分支 ...", or "切换到 ... 分支".
---

# Git Switch Branch

## Overview

Switch to a target Git branch by name, including local branches and remote-only branches.
Use the bundled script to match exact names first, then fuzzy matches, and avoid unsafe guesses.

## Workflow

1. Extract the branch name from the user command.
2. Run:

```bash
bash scripts/switch_branch.sh "<branch_name>"
```

3. If the script succeeds, confirm the active branch:

```bash
git branch --show-current
```

4. If the script reports ambiguity, show the candidates and ask the user to choose the exact branch name.
5. If the script reports no match, ask the user for a more precise branch name or whether to fetch remotes manually.

## Matching Rules

The script applies this order:

1. Exact local branch name.
2. Exact remote branch name (auto-creates local tracking branch when unambiguous).
3. Case-insensitive fuzzy local name contains match.
4. Case-insensitive fuzzy remote name contains match.

Prefer exact matches over fuzzy matches.
Do not auto-checkout when multiple candidates are found.

## Notes

Use `git checkout` for compatibility with the user's requested behavior.
Run from the repository root or any directory inside the same repository.
