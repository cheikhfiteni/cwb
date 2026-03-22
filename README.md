# cwb — Claude Worktree Branch

`cwb` launches Claude Code or Codex CLI in an isolated git worktree branched off your current branch. Unlike `claude -w`, which branches from the default branch, `cwb` preserves your current context.

By default, cwb stores repo-local worktrees under `<repo>/.cwb/worktrees/`. This avoids nesting child worktrees inside another worktree's `.claude/` directory, so removing the parent worktree does not implicitly wipe an active downstream cwb worktree.

## Installation

### Homebrew (recommended)

```bash
brew tap cheikhfiteni/tap
brew install cheikhfiteni/tap/cwb
```

Then add cwb to your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
source "$(brew --prefix)/opt/cwb/cwb"
```

Reload your shell (`source ~/.zshrc`) or open a new terminal.

### Manual

Clone the repo and source the script directly:

```bash
git clone https://github.com/cheikhfiteni/cwb.git ~/cwb
```

```bash
# ~/.zshrc or ~/.bashrc
source ~/cwb/cwb
```

### macOS toolchain bootstrap

To install the required CLIs (`claude`, `codex`, `ripgrep`) on macOS:

```bash
bash lib/setup/setup-macos.sh
```

The script is idempotent — it only installs what is missing. Override the Brewfile with `CWB_BREWFILE_URL=...` to test a different branch or fork.

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

1. **Prunes merged branches** — removes any `cwb/*` branches already merged into `origin/main`.
2. **Resolves branch/worktree target**:
   - if a worktree already exists for `cwb/<name>`, reuse it.
   - if local `cwb/<name>` exists, create a worktree from that branch.
   - if only remote `origin/cwb/<name>` exists, create local tracking branch and worktree.
   - otherwise create a new `cwb/<name>` branch and worktree.
3. **Optionally pulls from remote** for local branches after a `y/N` prompt.
4. **Sets up the environment** via `lib/lifecycle/cwb-worktree-env.sh`:
   - Symlinks `.env` files from the main repo into the worktree.
   - Creates `.env.local` stubs for worktree-specific overrides (ports, API URLs), auto-selecting free localhost ports for common `web/` runtimes.
   - Writes `docker-compose.override.yml` + `COMPOSE_PROJECT_NAME` to isolate Docker volumes per worktree.
   - Regenerates Python and iOS proto bindings when the repo provides compile scripts.
5. **Launches the selected CLI** (Claude Code or Codex) inside the worktree directory.
6. **Cleans up only newly created empty worktrees** via `lib/lifecycle/cwb-cleanup.sh`.

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
GRPC_PORT=50053
```

Keep URL values aligned with their port values. Use `bash lib/lifecycle/cwb-compose.sh ...` for Docker Compose commands so the cwb layer exports `.env.local` / `.env.override` before Compose evaluates the file.

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
- **Merged into main:** pruned automatically the next time any `cwb` command runs.

## Testing

Run the `cwb` test suite from repo root:

```bash
bash scripts/test_cwb.sh
```

The suite creates temporary git repos/remotes, stubs the CLI binaries (`claude`/`codex`), and verifies worktree/branch resolution behavior end-to-end.

## Releasing (maintainers)

cwb uses [Semantic Versioning](https://semver.org). The version lives in `cwb` at `CWB_VERSION="x.y.z"`. The Homebrew formula lives in the separate [`cheikhfiteni/homebrew-tap`](https://github.com/cheikhfiteni/homebrew-tap) repo (a generic tap that hosts all `cheikhfiteni` tools).

**Steps to cut a release:**

1. Update `CWB_VERSION` in `cwb`:
   ```bash
   # edit cwb: CWB_VERSION="x.y.z"
   ```

2. Commit, tag, and push:
   ```bash
   git add cwb
   git commit -m "release: vx.y.z"
   git tag vx.y.z
   git push origin main --tags
   ```
   GitHub automatically creates a source tarball at:
   `https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz`

3. Create a GitHub Release from the tag:
   ```bash
   gh release create vx.y.z --title "vx.y.z" --generate-notes
   ```

4. Compute the SHA256 of the tarball:
   ```bash
   curl -sL https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz | shasum -a 256
   ```

5. Update `Formula/cwb.rb` in the [`cheikhfiteni/homebrew-tap`](https://github.com/cheikhfiteni/homebrew-tap) repo:
   ```ruby
   url "https://github.com/cheikhfiteni/cwb/archive/refs/tags/vx.y.z.tar.gz"
   sha256 "<output from step 4>"
   ```
   A reference copy is kept at `Formula/cwb.rb` in this repo for convenience.

6. Commit and push the tap:
   ```bash
   git add Formula/cwb.rb
   git commit -m "cwb: vx.y.z"
   git push origin main
   ```

Users get the update on the next `brew upgrade cheikhfiteni/tap/cwb`.
