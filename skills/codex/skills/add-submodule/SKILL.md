---
name: add-submodule
description: Add a Git submodule under `third/` in the current repository and update AGENTS.md with submodule usage notes. Use when the user asks to add a submodule, add a repo under third/, or run `/add-submodule`.
---

# Add Submodule

Add a repository as `third/<name>` and document it in `AGENTS.md`.

## Workflow

1. Confirm the current directory is inside a Git repository.
2. Parse input as a repo URL plus optional `--name <dir>` and `--branch <branch>`.
3. Derive the default directory name from the repo URL, unless `--name` is provided.
4. Check whether `third/<dir>` already exists as a submodule or directory.
5. Run `git submodule add`, using `-b <branch>` only when requested.
6. Update or create `AGENTS.md` with a `### third/<dir>` section under `## Submodules`.
7. Report the submodule path, source URL, and suggested commit message.

## Rules

- Keep the submodule under `third/`.
- Do not overwrite an existing submodule section in `AGENTS.md`.
- If a path exists but is not the requested submodule, stop and ask for direction.
