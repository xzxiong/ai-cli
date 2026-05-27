---
name: test-debug-fix
description: Run a test, analyze failures, fix code, and iterate up to five rounds until passing. Use for `/test-debug-fix`, requests to debug failing tests, or automated test→fix loops.
---

# Test Debug Fix

Iteratively run a target test, diagnose failures, and apply minimal fixes.

## Workflow

1. Determine the correct test command and working directory from the project and test name.
2. Run the test with verbose output and save logs to `/tmp/<test>_<round>.log`.
3. Extract failure signatures: `FAIL`, `ERROR`, assertion failures, panic, traceback, timeout, or connection errors.
4. Classify the failure and inspect the relevant code.
5. Apply the smallest fix consistent with project style.
6. Run static checks where appropriate.
7. Re-run the test, up to five rounds.
8. Stop on pass, infrastructure failure, architecture-level uncertainty, or new unrelated failures caused by the last change.

## Project Hints

- MOI Go tests often require module-specific directories.
- Integration tests may need MatrixOne, MinIO, and OpenXML services.
- Use Go 1.24.x for MOI where sonic compatibility matters.
- Python checks should use project tooling such as Poetry and Ruff.
