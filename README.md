## Installation

1. Set secrets described in `compose.dev.yaml` / `compose.prod.yaml` in `.env` file
2. If need, copy `compose.override.yaml` from `examples` and modify it
3. **Local dev (infra in Docker, Tentura API on the host):** `docker compose up -d` (includes `compose.dev.yaml`) — then run the server from `packages/server`. **Production:** `docker compose -f compose.prod.yaml up -d`
4. Apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema and MeritRank-related triggers)
5. Upload `hasura/metadata.json` in Hasura console

### Generate secrets and etc

  `openssl genpkey -algorithm ed25519 -out jwt_private.pem`
  
  `openssl pkey -in jwt_private.pem -pubout -out jwt_public.pem`

## Development

The reverse proxy uses Caddy (official `caddy:alpine` image). For local dev, Caddy uses its automatic internal TLS for `localhost`. No proxy image build or certificate scripts are required.


## Backup and restore data

backup schema:
`docker exec -t postgres pg_dump -U postgres --schema-only --schema public > schema.sql`

backup data:
`docker exec -t postgres pg_dump --inserts -U postgres --data-only --schema public > data.sql`

backup schema and data:
`docker exec -t postgres pg_dump --inserts -U postgres --schema public > dump_all.sql`

restore:
`cat dump_all.sql | docker exec -i postgres psql -U postgres`
