# monorepo-rec-defaults

Fully configured example — ready to use with `cwb` straight away.

## What's pre-configured

| File | Purpose |
|---|---|
| `.cwb/port-specs` | Tells cwb which ports to allocate per worktree so parallel branches don't clash |
| `.cwb/hooks/post-worktree-setup.sh` | Appends derived `API_BASE_URL` from the allocated port and re-compiles protos |
| `.gitignore` (`# cwb ignores` block) | Gitignores `.cwb/worktrees/`, `.cwb.lock`, `docker-compose.override.yml` |

## Quick start

```bash
# Source cwb once in your shell profile
source /path/to/scripts/cwb/cwb

# Launch a worktree — cwb allocates ports, symlinks .env, runs the hook
cwb my-feature

# Inside the worktree, start the backend
bash scripts/cwb/lib/lifecycle/cwb-compose.sh up -d
```

When the worktree is created, cwb automatically:
1. Symlinks `.env` from the main repo into the worktree.
2. Writes `.env.local` with unique ports (e.g. `API_PORT=8100`) so this
   worktree doesn't conflict with others running in parallel.
3. Writes `docker-compose.override.yml` with `COMPOSE_PROJECT_NAME` to isolate
   Docker volumes from other worktrees.
4. Runs `.cwb/hooks/post-worktree-setup.sh` to append `API_BASE_URL` and
   recompile protos.

## Layout

```
.
├── .cwb/
│   ├── port-specs                    # port allocation config
│   └── hooks/post-worktree-setup.sh  # derive URLs + compile protos
├── .env                              # secret template (gitignored: .env.local)
├── .gitignore                        # includes cwb ignores block
├── docker-compose.yml                # api + worker + postgres
├── api/Dockerfile
├── worker/Dockerfile
├── proto/
│   ├── buf.yaml
│   └── example/v1/example.proto
├── scripts/
│   └── compile_protos.sh
└── frontend/
    └── package.json
```

## Running without cwb

```bash
cp .env .env.local
# edit .env.local — fill in POSTGRES_PASSWORD and SECRET_KEY
docker compose --env-file .env.local up -d
```

## Frontend

```bash
cd frontend
npm install
npm run dev
```
