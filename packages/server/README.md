## Build server

  `dart run build_runner build -d`
  `dart compile exe bin/tentura.dart`

## Tests

Most server tests use mocked repository ports and need no database.

A small set of **Postgres integration tests** (tagged `pg`) exercise real Drift
`customSelect` / `customStatement` against a live database. PR CI runs
`dart test --exclude-tags pg`; a **nightly** GitHub Actions job
(`.github/workflows/pg-integration-nightly.yml`) runs `dart test --tags pg`
against `vbulavintsev/postgres-tentura` + MeritRank service containers.
Locally use `dart test` (skipped when Postgres is not reachable) or
`dart test --tags pg` for integration only (`docker compose up -d meritrank postgres`).
Postgres defaults to `127.0.0.1:5432` (override via `POSTGRES_HOST` /
`POSTGRES_PORT` / `POSTGRES_PASSWORD`).

| File | What it covers |
|------|----------------|
| `test/app/di_smoke_test.dart` | Prod/dev DI graph boots against live Postgres |
| `test/data/repository/email_auth_transaction_repository_test.dart` | `consumeByToken` raw SQL + `timestamptz` RETURNING workaround (`WORKAROUNDS.md` §4) |

```bash
cd packages/server && dart test
# CI: dart test --exclude-tags pg
# integration only: dart test --tags pg
```

## Build docker image

  Replace version tag with actual
  `docker build --no-cache -t alexandrim0/tentura-service:v0.6.4 .`

## Use REST Client

  Create and fill `rest/.env` file
