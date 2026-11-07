## Build server

  `dart run build_runner build -d`
  `dart compile exe bin/tentura.dart`

## Tests

Most server tests use mocked repository ports and need no database.

Tests that need live services are selected by tags; `dart_test.yaml` holds
the authoritative description of each one:

| Tag | Meaning |
|-----|---------|
| `pg` | Needs a live Postgres (most integration tests build their own disposable database). |
| `mr` | Also reaches the shared MeritRank container; run with `-j 1`, apart from the rest of `pg`. |
| `multi-connection` | Sizes its own pool above one connection; excluded from the pool-size-1 run, run with `-j 1`. |
| `perf` / `load` | Perf recorder and load suites (also `pg` + `mr`); opt-in only. |
| `repo-files` | Reads files outside `packages/server` (docs, scripts, workflows, client). |
| `toolchain` | Re-runs the analyzer gates; CI runs those directly and excludes this tag. |

Start the services with `docker compose up -d meritrank postgres`. Postgres
defaults to `127.0.0.1:5432` (override via `POSTGRES_HOST` / `POSTGRES_PORT` /
`POSTGRES_PASSWORD`). Some `pg` tests use the default database and expect it
migrated: `dart run bin/utils/run_migrations_once.dart`.

From the repo root, `scripts/run_tests.sh` runs each profile with the right
tags and `-j` (`server-unit`, `server-pg`, `server-mr`, `server-files <paths>`;
see its header). The plain equivalents:

```bash
cd packages/server
dart test --exclude-tags pg,toolchain                  # unit tests, no services
dart test --tags pg --exclude-tags mr,perf,load        # Postgres suites
dart test --tags mr --exclude-tags perf,load -j 1      # also needs MeritRank
dart test --tags repo-files                            # files outside the package
```

## Build docker image

  Replace version tag with actual
  `docker build --no-cache -t alexandrim0/tentura-service:v0.6.4 .`

## Use REST Client

  Create and fill `rest/.env` file
