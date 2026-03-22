# monorepo-no-setup

Bare example monorepo — no cwb configuration applied yet.

## Quick start

Before using `cwb`, run the repo-setup assistant to add `.gitignore` entries
and any cwb config files this repo needs:

```bash
cwb cwb-setup
```

Follow the prompts, then launch a worktree as normal:

```bash
cwb my-feature
```

## Layout

```
.
├── .env                          # secret template (copy to .env.local)
├── .gitignore
├── docker-compose.yml            # api + worker + postgres
├── api/Dockerfile
├── worker/Dockerfile
├── proto/
│   ├── buf.yaml
│   └── example/v1/example.proto
└── frontend/
    └── package.json
```

## Running the backend locally (no cwb)

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
