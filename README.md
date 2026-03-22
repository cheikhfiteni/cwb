# cwb — Claude Worktree Branch

`cwb` launches Claude Code or Codex CLI in an isolated git worktree branched off your current branch. Unlike `claude -w`, which branches from the default branch, `cwb` preserves your current context.

By default, cwb stores repo-local worktrees under `<repo>/.cwb/worktrees/`. This avoids nesting child worktrees inside another worktree's `.claude/` directory, so removing the parent worktree does not implicitly wipe an active downstream cwb worktree.

## Setup

Source the `cwb` file in your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
source /path/to/cwb/cwb
```

Reload your shell (`source ~/.zshrc`) or open a new terminal.

On macOS, bootstrap the `cwb` toolchain with:

```bash
bash scripts/cwb/lib/setup/setup-macos.sh
```

The script is idempotent:
- it downloads the current [`scripts/cwb/lib/setup/Brewfile`](scripts/cwb/lib/setup/Brewfile) from GitHub and runs `brew bundle`
- it only runs `xcode-select --install` if Command Line Tools are missing
- it only runs the Flowdeck installer if `flowdeck` is not already on `PATH`

Override the Brewfile source with `CWB_BREWFILE_URL=...` if you need to test a different branch or fork.

## CLI Selection

`cwb` supports both Claude Code and Codex CLI. Use the `set-default` command to choose which CLI to launch:

```bash
cwb set-default=claude   # Use Claude Code (default)
cwb set-default=codex    # Use Codex CLI
cwb cwb-setup            # Open the repo-setup worktree with the default setup prompt
cwb --set-defaults       # Interactively set shared defaults like tmux / yolo
cwb --status             # Show version and persisted preferences
```

CLI choice and shared defaults are persisted in `~/.cwb/.cwb-prefs`, so they survive across repo clones and install sessions until changed.

Current upstream CLI references:
- Codex CLI reference: <https://developers.openai.com/codex/cli/reference>
- Claude Code CLI reference: <https://code.claude.com/docs/en/cli-reference>

## Configuration

When using Codex CLI, `cwb` automatically loads project context from `.codex/config.toml`, which includes:
- Multi-agent mode enabled for parallel sub-agent work
- Cached web search for faster responses
- Project documentation fallback to load both `AGENTS.md` and `CLAUDE.md`

## Usage

```bash
cwb                              # auto-generated name (e.g. "swift-river-stone")
cwb fix-auth                     # named worktree on branch cwb/fix-auth
cwb fix-auth "add logout button" # pass a prompt to the CLI
cwb -- "continue refactor"       # open interactive picker, then pass prompt
cwb fix-auth --tmux              # run in a new tmux session
cwb fix-auth --copy-volumes=false # skip Docker volume isolation
```

Everything after the optional name and cwb-specific flags is forwarded to the selected CLI (Claude Code or Codex).

## Flags

| Flag | Default | Description |
|---|---|---|
| `--tmux` | off | Run the CLI in a new tmux session (`cwb-<name>`) |
| `--copy-volumes=true\|false` | `true` | Prefix Docker named volumes with worktree name for isolation |

## What it does

1. **Prunes merged branches** — removes any `cwb/*` branches already merged into `origin/staging`.
2. **Resolves branch/worktree target**:
   - if a worktree already exists for `cwb/<name>`, reuse it.
   - if local `cwb/<name>` exists, create a worktree from that branch.
   - if only remote `origin/cwb/<name>` exists, create local tracking branch and worktree.
   - otherwise create a new `cwb/<name>` branch and worktree.
3. **Optionally pulls from remote** for local branches after a `y/N` prompt.
4. **Sets up the environment** via `scripts/cwb/lib/lifecycle/cwb-worktree-env.sh`:
   - Symlinks `.env` files from the main repo into the worktree.
   - Creates `.env.local` stubs for worktree-specific overrides (ports, API URLs), auto-selecting free localhost ports for common `web/` runtimes.
   - Writes `docker-compose.override.yml` + `COMPOSE_PROJECT_NAME` to isolate Docker volumes per worktree.
   - Regenerates Python and iOS proto bindings when the repo provides compile scripts.
5. **Launches the selected CLI** (Claude Code or Codex) inside the worktree directory.
6. **Cleans up only newly created empty worktrees** via `scripts/cwb/lib/lifecycle/cwb-cleanup.sh`.

## Interactive picker

If you run `cwb` with no name, or run `cwb -- <cli args>`, `cwb` opens a picker:

- `blue` option at the top: create a new random branch.
- `green` section: existing worktrees.
- `yellow` section: `cwb/*` branches not currently checked out in any worktree (local and/or remote).

You can press enter to create a new random branch, choose an item by number, or type a name directly.

## Environment overrides

Each worktree gets a `.env.local` stub next to every `.env` symlink. Use it to run services on different ports so the worktree doesn't conflict with your main dev environment:

```bash
# web/.env.local (example)
FASTAPI_PORT=8001
API_BASE_URL=http://localhost:8001
PROMPT_SERVICE_PORT=8002
PROMPT_SERVICE_URL=http://localhost:8002
MOBILE_BACKEND_PORT=8091
MOBILE_API_BASE_URL=http://localhost:8091
GRPC_PORT=50053
PREVIEW_ATC_GRPC_URL=localhost:50053
HATCHET_SERVER_PORT=8889
HATCHET_GRPC_PORT=7078
EVAL_DASHBOARD_PORT=8502
EVAL_DASHBOARD_UI_PORT=5174
```

Keep the URL values aligned with the port values. In worktrees, `cwb` will try to pick available ports for you on first run. Use `bash scripts/cwb/lib/lifecycle/cwb-compose.sh ...` for Docker Compose commands so the cwb layer exports `.env.local` / `.env.override` before Compose evaluates the file.

`.env.local` is gitignored and never committed. Do not create `.env.local` in the main repo.

## Docker volume isolation

By default, `cwb` sets the Docker Compose project name to `cwb-<worktree-name>`, which prefixes all named volumes:

```
hatchet_postgres_data → cwb-swift-river-stone_hatchet_postgres_data
```

This ensures parallel worktrees never share databases or state. Pass `--copy-volumes=false` to opt out.

## Lifecycle

- **Active worktree with changes:** kept after the CLI exits. Resume with `cd .cwb/worktrees/<name>`.
- **Clean worktree (no changes):** automatically removed along with its branch.
- **Merged into staging:** pruned automatically the next time any `cwb` command runs.

## Testing

Run the `cwb` test suite from repo root:

```bash
bash scripts/test_cwb.sh
```

The suite creates temporary git repos/remotes, stubs the CLI binaries (`claude`/`codex`), and verifies worktree/branch resolution behavior end-to-end.
