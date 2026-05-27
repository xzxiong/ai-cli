---
name: run-all-tasks
description: Execute all tasks from a `.kiro/specs/*/tasks.md` file with checkbox checkpointing and resumability. Use for `run all tasks`, `执行所有任务`, `continue/继续` in a spec task context, or `/run-all-tasks`.
---

# Run All Tasks

Execute Kiro spec tasks with persistent progress in `tasks.md`.

## Workflow

1. Locate the target spec under `.kiro/specs/`; if multiple specs match and no name is provided, ask the user.
2. Read `tasks.md` and find the first incomplete non-optional checkbox.
3. Execute tasks in order, reading relevant files before each change.
4. After each completed task, immediately mark its checkbox `- [x]`.
5. Skip optional tasks marked `- [ ]*` unless the user explicitly requests them.
6. For checkpoint/build tasks, run the requested build or default `go build ./...`; fix failures up to three rounds, then stop if still failing.
7. Mark parent tasks complete only after their subtasks are complete.
8. Report completed, skipped, modified files, and any blockers.

## Rules

- Checkpoint state lives in `tasks.md`; support resume from the first incomplete task.
- Do not skip compile errors at checkpoints.
- Do not perform unrelated refactors while executing tasks.
