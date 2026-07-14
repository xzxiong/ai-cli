---
name: gh-comment-file
description: Replace a GitHub issue or pull-request comment body with the contents of a local file. Use for commands like `cc github-comment-url`, `内容是文件路径，请补上文件内容`, `update this issuecomment from file`, or when a GitHub comment currently contains only a local file path that should be expanded into the file's actual Markdown/text content.
---

# GitHub Comment File

Update an existing GitHub issue/PR comment from a local file without changing code.

## Workflow

1. Parse the GitHub comment URL.
   - Support PR issue-comment URLs such as `https://github.com/<owner>/<repo>/pull/<n>#issuecomment-<comment_id>`.
   - Support issue-comment URLs such as `https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<comment_id>`.
   - Extract `owner`, `repo`, and numeric `comment_id`.
2. Fetch the comment:
   - `gh api repos/<owner>/<repo>/issues/comments/<comment_id> --jq '{id,user:.user.login,body,html_url}'`
3. Interpret the current body or user-provided text as a file path when it looks like a local path.
   - Strip a leading `@` before reading, e.g. `@/tmp/report.md`.
   - Expand `~` if present.
   - If the file does not exist or the body is not a path, ask one concise clarification.
4. Read the file content from disk and check the size.
   - GitHub issue comments have practical body limits; if the file is very large, summarize the issue and ask before truncating or splitting.
   - Preserve Markdown exactly; do not rewrite the report while posting it.
5. Patch the comment with the file contents:
   - `jq -Rs '{body: .}' <file> | gh api --method PATCH repos/<owner>/<repo>/issues/comments/<comment_id> --input - --jq '{id,updated_at,html_url,body_len:(.body|length)}'`
   - Do not use `-f body=@<file>` or `-F body=@<file>` here; with `gh api` form fields this can post the literal path string instead of the file contents.
6. Verify by fetching the comment again.
   - Confirm the body no longer contains the local file path.
   - Confirm a recognizable heading or prefix from the file is present.

## Rules

- Do not use `review-fix`; this skill edits GitHub comment text only and does not modify repository code.
- Do not create a new comment when the user gave a comment URL; update that exact comment.
- Do not expose secrets from the file. If the file appears to contain tokens, passwords, private keys, or credentials, stop and ask before posting.
- Report only the updated comment URL and the verification result unless the user asks for more detail.
