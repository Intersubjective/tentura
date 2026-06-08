## Build server

  `dart run build_runner build -d`
  `dart compile exe bin/tentura.dart`

## Tests

Most server tests use mocked repository ports and need no database.

A small set of **Postgres integration tests** exercise real Drift `customSelect` /
`customStatement` against a live database. They are **skipped** when Postgres is
not reachable (CI has no Postgres service). Run them locally with dev compose
or any Postgres on `127.0.0.1:5432` (override via `POSTGRES_HOST` /
`POSTGRES_PORT` / `POSTGRES_PASSWORD`).

| File | What it covers |
|------|----------------|
| `test/data/repository/email_auth_transaction_repository_test.dart` | `consumeByToken` raw SQL + `timestamptz` RETURNING workaround (`WORKAROUNDS.md` §4) |

```bash
cd packages/server && dart test
# skipped integration tests show as ~ (tilde), exit 0
# with local Postgres up, those tests run instead of skip
```

## Build docker image

  Replace version tag with actual
  `docker build --no-cache -t alexandrim0/tentura-service:v0.6.4 .`

## Use REST Client

  Create and fill `rest/.env` file
