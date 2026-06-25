---
name: spec-worktree
description: Create a Kiro-style spec, create a Git branch and worktree, sync the spec into the worktree, and open an IDE window. Use for `/spec-worktree` or requests to start feature work in a separate worktree.
---

# Spec Worktree

Create a spec-backed Git worktree for isolated implementation.

## Inputs

- Feature description.
- Optional `--branch <name>`, `--from <branch>`, `--no-ide`, `--worktree-dir <path>`.

## Workflow

1. Create `.kiro/specs/<feature-name>/` with `requirements.md`, `design.md`, and `tasks.md`.
2. Derive branch name as `feat-<spec-name>` or `fix-<spec-name>` unless `--branch` is provided.
3. Use `--from` as the base branch, defaulting to `dev`.
4. Fetch origin and create or validate the branch.
5. Create a Git worktree at `worktree/<branch>` unless overridden.
6. Ensure `worktree/` is ignored where appropriate.
7. Copy `requirements.md`, `design.md`, `tasks.md`, and `.config.kiro` when present into the worktree's `.kiro/specs/<feature-name>/`.
8. Open the worktree in the IDE unless `--no-ide` is set.
9. Report spec path, branch, worktree path, and next command.

## Safety

- If the branch or worktree already exists with different intent, ask before reusing it.
- Do not delete worktrees or branches unless explicitly requested.
- If the remote branch already exists, track it instead of creating an unrelated local branch.
- Spec sync is one-way from the main repo to the worktree unless the user asks otherwise.
