# cwb Examples

Two minimal monorepos that demonstrate how `cwb` handles different repo states.

## What's here

| Directory | Description |
|---|---|
| [`monorepo-rec-defaults/`](monorepo-rec-defaults/) | Fully configured — `.cwb/port-specs`, a post-setup hook, gitignored secrets. Run `cwb` straight away. |
| [`monorepo-no-setup/`](monorepo-no-setup/) | Bare monorepo — no cwb config. Run `cwb setup-repo` first. |

Both examples share the same monorepo shape: a two-container backend (API + worker) behind
docker compose, a protobuf-defined service interface, a separate frontend runtime, and
example secrets in `.env`.

---

## Running the configured example

```bash
# From repo root — source cwb if you haven't already
source scripts/cwb/cwb

# Launch a worktree branched off your current branch
cwb my-feature scripts/cwb/examples/monorepo-rec-defaults
```

`cwb` will:
1. Create an isolated git worktree.
2. Symlink `.env` into the worktree and write a `.env.local` stub with unique ports
   (read from `.cwb/port-specs`).
3. Write `docker-compose.override.yml` and set `COMPOSE_PROJECT_NAME` so volumes
   are isolated from other worktrees.
4. Run `.cwb/hooks/post-worktree-setup.sh` to inject derived URLs and recompile protos.

Start the backend from inside the worktree:

```bash
bash scripts/cwb/lib/lifecycle/cwb-compose.sh up -d   # honours .env.local port overrides
```

---

## Running the bare example (setup-repo first)

`monorepo-no-setup/` has no cwb config. Before launching a worktree, run the
repo-setup assistant to add the `.gitignore` block and any per-project cwb files:

```bash
cwb cwb-setup scripts/cwb/examples/monorepo-no-setup
```

Follow the prompts. Once setup is done, use `cwb` as normal.

---

## Example layout (both monorepos)

```
.
├── .env                    # example secrets (gitignored)
├── .gitignore
├── docker-compose.yml      # multi-container backend (api + worker + postgres)
├── api/
│   └── Dockerfile
├── worker/
│   └── Dockerfile
├── proto/
│   ├── buf.yaml
│   └── example/v1/example.proto
└── frontend/
    └── package.json        # separate frontend runtime
```

`monorepo-rec-defaults/` adds:

```
├── .cwb/
│   ├── port-specs                    # port allocation for worktree .env.local
│   └── hooks/post-worktree-setup.sh  # derive URLs + compile protos
└── scripts/
    └── compile_protos.sh
```
