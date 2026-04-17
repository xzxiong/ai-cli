---
name: update-pr-desc
description: Draft or update GitHub pull request descriptions from a PR URL or PR number using the real diff, touched files, commits, and existing PR body. Use when the user says "update pr desc", "refresh PR description", "rewrite PR body", "根据代码更新 PR 描述", or asks to sync a PR description with the latest changes. Preserve manually maintained issue or document links from the existing `## 相关链接` or `## Related Links` section, and use the GitHub REST API when applying the new body.
---

# Update PR Description

Write PR descriptions from evidence in the code, not from the PR title alone.

## Workflow

1. Resolve the repo and PR from the URL, PR number, or current repository.
2. Gather PR metadata with `gh pr view`.
3. Inspect the diff selectively with `gh pr diff`; skip generated or low-signal files unless they imply a real behavior change.
4. Extract the existing `## 相关链接` or `## Related Links` section and preserve it verbatim.
5. Draft the new PR body with the structure in `references/template.md`.
6. If the user explicitly asks to apply or update the PR body, patch it via `gh api`.
7. Verify the updated body with `gh pr view`.

## Gather Context

Use `gh` first:

```bash
gh pr view <PR> --json number,title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,files,commits,labels,url
gh pr diff <PR>
```

Prefer local repository context when available:
- Read full changed files, not just the diff hunk, when a summary depends on surrounding logic.
- Skim tests, routing, config, schema, and docs touched by the PR.
- Skip generated files such as swagger artifacts, lock files, and vendored outputs unless they hide a meaningful contract change.

If the user only asks to improve or rewrite the description, stop at a draft.
If the user explicitly asks to update, apply, or sync the PR body, write it back to GitHub.

## Content Rules

- Mirror the language already used in the PR title/body or the user's request.
- Summarize what changed, why it changed, and how the change is used or validated.
- Group important changes by module or subsystem instead of listing files with no narrative.
- Include a call chain or data flow block only when it helps explain non-trivial behavior changes.
- Mark checkboxes conservatively; do not claim tests, docs, or environment validation without evidence.
- Preserve manually authored issue links, design docs, and API docs from the old links section.
- If the diff is too large to inspect fully, say what was sampled and avoid overclaiming coverage.

## Apply Changes

Do not rely on `gh pr edit --body` when repository settings may cause GraphQL failures.
Prefer the REST endpoint when updating the body:

```bash
gh api repos/<owner>/<repo>/pulls/<PR> -X PATCH -F "body=@/tmp/pr-body.md"
```

Resolve `<owner>/<repo>` from the PR URL or the current git remote.
Write the drafted body to a temp file first, apply it, then verify with `gh pr view <PR> --json body`.

## Reference

Use `references/template.md` for the section template, links-preservation rule, diagram selection, and checkbox heuristics.
