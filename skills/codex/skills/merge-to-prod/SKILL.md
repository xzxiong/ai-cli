---
name: merge-to-prod
description: "Create a production sync PR by branching from latest origin/main, merging latest origin/prod, summarizing commits that will go to prod, pushing the merge branch, and opening a PR to prod. Use for `merge to prod`, `sync main to prod`, `pr to prod`, `deploy to prod`, or production promotion PR requests."
---

# Merge To Prod

Create a branch from latest `origin/main`, merge latest `origin/prod`, and open a production PR.

## Inputs

- Optional `--dry-run`: fetch, create/check the merge branch, merge prod, and show commits that would be promoted; do not push or create a PR.

## Workflow

1. Fetch current production branches:
   - `git fetch origin main prod`
2. Create a branch named `merge-main-to-prod-<YYMMDD>` from `origin/main`.
   - If it already exists, append `-v2`, `-v3`, etc.
3. Merge `origin/prod` into the branch.
   - If conflicts occur, resolve them conservatively and verify no conflict markers remain.
   - If conflicts cannot be resolved safely, stop and report the files.
4. Show the production delta with `git log --oneline origin/prod..HEAD`.
   - In `--dry-run` mode, stop here after reporting commit count and summary.
5. Push the branch to origin.
6. Create a PR with base `prod`.
7. Generate the PR title and body from the commits and meaningful production-impacting diff.

## PR Title

Use:

```text
deploy(prod): {<components>} <versions> (<YYMMDD>)
```

Detect components from commit messages plus relevant file changes. Only consider public code, `Pulumi.yaml`, and `Pulumi.prod.yaml`; ignore `Pulumi.new-dev.yaml`, `Pulumi.qa.yaml`, and other non-prod environment config.

Component hints:

- `moi-taas`: TAAS changes.
- `moi-core`: moi-core charts/services such as moi-backend, moi-catalog, moi-mowl, go-worker, python-worker.
- `moi4x`: MOI 4.x pipeline under cos-component, mowl, catalog-service, workflow-scheduler.
- `moi5x`: MOI 5.x cloud-service changes.
- `mo`: MatrixOne database changes.
- `apiserver`, `unoserver`, `moi-frontend`, `infra`: matching service or infrastructure changes.
- fallback: `config-updates`.

Extract image/tag versions from prod-relevant diffs when present. If no version is clear, omit versions.

## PR Body

```markdown
## Summary
- <grouped commit summary, no more than 10 bullets>

## Commits (<N>)
- <commit summary, no more than 20 lines>
```

## Output

Report branch, merge status, commit count, push status, and PR URL.
