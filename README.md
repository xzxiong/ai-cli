# ai-cli

`ci-cli` is a helper CLI for syncing skills/knowledge across tools.

## Build

```bash
go build -o ci-cli ./cmd/ci-cli
# or:
make build BINARY=bin/ci-cli
```

## Makefile

```bash
make help
make build
make test
make skills-install TOOLS=all
make skills-upload TOOLS=codex
```

## Usage

Install from this repo to local global tool directories:

```bash
./ci-cli skills --install --tools codex
./ci-cli skills --install --tools codex,kiro,claude-code
./ci-cli skills --install --tools all
```

Upload local global skills/knowledge into this repo and run `diff -> merge -> commit -> push`:

```bash
./ci-cli skills --upload --tools codex
./ci-cli skills --upload --tools all
./ci-cli skills --uplaod --tools kiro
```

Supported values for `--tools`:

- `codex`
- `kiro`
- `claude-code` (alias: `claude`)
- `all`

`--tools` defaults to `all` when omitted.

Default local paths:

- `codex`: skills at `$CODEX_HOME/skills`, knowledge at `$CODEX_HOME/memories` (fallback `$CODEX_HOME/knowledge`, default root `~/.codex`)
- `kiro`: skills at `$KIRO_HOME/skills`, knowledge at `$KIRO_HOME/steering` (fallback `$KIRO_HOME/knowledge`, default root `~/.kiro`)
- `claude-code`: auto-detect root from `$CLAUDE_HOME`, `~/.claudecode`, `~/.claude-code`, `~/.claude`; sync `skills` and `knowledge` under that root

## Knowledge Management Notes

- `codex`: knowledge is memory-oriented. On this machine, actual knowledge storage is `~/.codex/memories`; no active `~/.codex/knowledge` directory was found.
- `kiro`: knowledge is steering-oriented. On this machine, active project knowledge is `~/.kiro/steering` (for example `project-goals.md`), not `~/.kiro/knowledge`.
- `claude-code`: this machine currently has `~/.claudecode` and `~/.claude`, but no visible `skills`/`knowledge` content yet. The CLI now tries multiple roots and picks existing paths first.
