# ai-cli

`ci-cli` is a helper CLI for syncing skills/knowledge/learning/agent data across tools.

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
make install TOOLS=all
make upload TOOLS=codex
```

## Usage

Install from this repo to local global tool directories:

```bash
./ci-cli skills --install --tools codex
./ci-cli skills --install --tools codex,kiro,claude-code
./ci-cli skills --install --tools all
```

Install into project-level tool directories:

```bash
./ci-cli skills --install --tools kiro --project github.com/matrixorigin/matrixflow
./ci-cli skills --install --tools kiro --project /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow
```

Upload local global skills/knowledge/learning/agent data into this repo and run `diff -> merge -> commit -> push`:

```bash
./ci-cli skills --upload --tools codex
./ci-cli skills --upload --tools all
```

Upload from project-level tool directories:

```bash
./ci-cli skills --upload --tools kiro --project github.com/matrixorigin/matrixflow
```

Supported values for `--tools`:

- `codex`
- `kiro`
- `claude-code` (alias: `claude`)
- `all`

`--tools` defaults to `all` when omitted.

`--project` is optional. When set, the CLI resolves project-level directories instead of global home directories. You can pass either:

- a project key configured in `~/.ai-cli.yaml`
- an absolute project path

`--config` is optional and defaults to `~/.ai-cli.yaml`. If the file does not exist, `ai-cli` creates it automatically.

Default local paths:

- `codex`: skills at `$CODEX_HOME/skills`, knowledge at `$CODEX_HOME/memories` (fallback `$CODEX_HOME/knowledge`), agent at `$CODEX_HOME/agents` (fallback `$CODEX_HOME/agent`, default root `~/.codex`)
- `kiro`: skills at `$KIRO_HOME/skills`, knowledge at `$KIRO_HOME/steering` (fallback `$KIRO_HOME/knowledge`), learning at `$KIRO_HOME/learning`, agent at `$KIRO_HOME/agents` (default root `~/.kiro`)
- `claude-code`: auto-detect root from `$CLAUDE_HOME`, `~/.claudecode`, `~/.claude-code`, `~/.claude`; sync `skills`, `knowledge`, and `agents` (fallback `agent`) under that root

## Knowledge Management Notes

- `codex`: knowledge is memory-oriented. On this machine, actual knowledge storage is `~/.codex/memories`; no active `~/.codex/knowledge` directory was found.
- `kiro`: knowledge is steering-oriented. On this machine, active project knowledge is `~/.kiro/steering` (for example `project-goals.md`), not `~/.kiro/knowledge`.
- `kiro`: `learning` is synced separately from `steering/knowledge` and is uploaded into `skills/kiro/learning`.
- `claude-code`: this machine currently has `~/.claudecode` and `~/.claude`, but no visible `skills`/`knowledge` content yet. The CLI now tries multiple roots and picks existing paths first.

## Config

Example `~/.ai-cli.yaml`:

```yaml
global:
  tools:
    kiro:
      root: /Users/jacksonxie/.kiro
    codex:
      root: /Users/jacksonxie/.codex

projects:
  github.com/matrixorigin/matrixflow:
    root: /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow
    tools:
      kiro:
        root: /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow/.kiro
```

配置语义是分开的：

- 不传 `--project` 时，只读取 `global.tools`
- 传 `--project github.com/matrixorigin/matrixflow` 时，只读取 `projects.github.com/matrixorigin/matrixflow.tools`

`root` 只是该工具目录根路径的简写，CLI 会按工具类型推导：

- `kiro`: `skills` / `steering` / `learning` / `agents`
- `codex`: `skills` / `memories` / `agents`
- `claude-code`: `skills` / `knowledge` / `agents`

如果需要，也可以显式写完整路径：

```yaml
projects:
  github.com/matrixorigin/matrixflow:
    root: /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow
    tools:
      kiro:
        skills:
          - /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow/.kiro/skills
        knowledge:
          - /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow/.kiro/steering
        learning:
          - /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow/.kiro/learning
        agents:
          - /Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow/.kiro/agents
```
