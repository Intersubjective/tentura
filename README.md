## Installation

1. Copy `.env.example` → `.env` and set **all secrets** (JWT, Postgres, Hasura admin, S3, OAuth, Resend, Firebase, etc.). `compose.prod.yaml` passes variable names through from `.env`.
2. **VPS / staging only:** copy `examples/compose.override.example.yaml` → `compose.override.yaml` and adjust **non-secret** per-host settings (dev Hasura console, image tag, postgres tuning, pgAdmin). Never put secrets in the override file.
3. **Local dev (infra in Docker, Tentura API on the host):** `docker compose up -d` (includes `compose.dev.yaml`) — then run the server from `packages/server`. **Production / VPS:** `docker compose -f compose.prod.yaml up -d` (auto-merges `compose.override.yaml` when present), or `./deploy.sh`.
4. After changing `.env`, recreate affected containers: `docker compose up -d --force-recreate tentura hasura` (env is baked in at container create time).
5. Apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema and MeritRank-related triggers)
6. Apply Hasura metadata: `./scripts/hasura_apply_metadata.sh` (with compose dev Hasura on `http://127.0.0.1:8080`), or upload `hasura/metadata.json` in the Hasura console

### Compose layout (VPS)

| File | Role |
|------|------|
| `compose.prod.yaml` | Committed stack definition; lists env var names |
| `compose.override.yaml` | Per-host, gitignored; dev flags, extra services, tuning |
| `.env` | Gitignored secrets and host-specific values |

### Generate secrets and etc

  `openssl genpkey -algorithm ed25519 -out jwt_private.pem`

  `openssl pkey -in jwt_private.pem -pubout -out jwt_public.pem`

## Development

The reverse proxy uses Caddy (official `caddy:alpine` image). For local dev, Caddy uses its automatic internal TLS for `localhost`. No proxy image build or certificate scripts are required.

### Architecture & code guidelines

- `**DEV_GUIDELINES.md`** — includes **layer boundaries** (server ports, client use cases / cubits, `tentura_lints`, CI analyze).
- `**.cursor/rules/`** — `architecture.mdc` (full detail), `quick-reference.mdc` (one-line checklist, always on for agents).

## Backup and restore data

backup schema:
`docker exec -t postgres pg_dump -U postgres --schema-only --schema public > schema.sql`

backup data:
`docker exec -t postgres pg_dump --inserts -U postgres --data-only --schema public > data.sql`

backup schema and data:
`docker exec -t postgres pg_dump --inserts -U postgres --schema public > dump_all.sql`

restore:
`cat dump_all.sql | docker exec -i postgres psql -U postgres`