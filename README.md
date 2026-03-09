## Installation

1. Set secrets described in `compose.yaml` in `.env` file
2. If need, copy `compose.override.yaml` from `examples` and modify it
3. Run containers (docker compose up -d)
4. `chown nobody:nogroup /etc/nginx/cert`(acme.autossl cert storage)
5. apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema and MeritRank-related triggers)
6. upload `hasura/metadata.json` in Hasura console

### Generate secrets and etc

  `openssl genpkey -algorithm ed25519 -out jwt_private.pem`
  
  `openssl pkey -in jwt_private.pem -pubout -out jwt_public.pem`

## Development

1. Run `./openresty/scripts/create_cert_and_keys.sh`
2. Build images (docker build --no-cache -t alexandrim0/openresty-tentura:vX.Y.Z .)


## Backup and restore data

backup schema:
`docker exec -t postgres pg_dump -U postgres --schema-only --schema public > schema.sql`

backup data:
`docker exec -t postgres pg_dump --inserts -U postgres --data-only --schema public > data.sql`

backup schema and data:
`docker exec -t postgres pg_dump --inserts -U postgres --schema public > dump_all.sql`

restore:
`cat dump_all.sql | docker exec -i postgres psql -U postgres`

## Minio

Start Minio Console
`docker run -it --entrypoint=/bin/sh minio/mc`

Set credentials
`mc alias set minio http://localhost:9000 login password`

Grant access to anonymous on `mybucket`
`mc anonymous set download minio/mybucket`

Create access\secret keys
`mc admin accesskey create minio/`
