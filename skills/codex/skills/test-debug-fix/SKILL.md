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
5. Track timing by round. If runtime worsens by more than 50%, treat the last fix as suspect and reassess before continuing.
6. Apply the smallest fix consistent with project style.
7. Run static checks where appropriate.
8. Re-run the test, up to five rounds.
9. Stop on pass, infrastructure failure, architecture-level uncertainty, or new unrelated failures caused by the last change.

## Project Hints

- MOI Go tests often require module-specific directories.
- Integration tests may need MatrixOne, MinIO, and OpenXML services.
- Use Go 1.24.x for MOI where sonic compatibility matters.
- Python checks should use project tooling such as Poetry and Ruff.

## Command Hints

- moi-core integration: `go test . -run <Test> -v -timeout 120s -count=1` in `moi-core/tests`.
- moi-core workers: `go test ./... -run <Test> -v -timeout 60s -count=1` in `moi-core/workers/go-worker`.
- moi-core catalog: `go test ./... -run <Test> -v -timeout 60s -count=1` in `moi-core/catalog`.
- moi-core SDK: `go test ./... -run <Test> -v -timeout 60s -count=1` in `moi-core/go-sdk`.
- Python: `poetry run pytest <path> -v --tb=long`.
- .NET: `dotnet test --filter <Test> -v`.
