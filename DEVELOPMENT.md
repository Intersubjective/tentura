# Development Setup

## Prerequisites

- Docker & Docker Compose (v2+)
- Flutter SDK (stable channel, currently 3.41+)
- Dart SDK (bundled with Flutter)

## Quick Start

```bash
# 1. Create .env from the example (once)
cp .env.example .env

# 2. Start infrastructure (Postgres, MeritRank, Hasura, MinIO, pgAdmin)
docker compose up -d

# 3. Start the Tentura API server (port 2080)
./scripts/run-server-local.sh

# 4. In a second terminal — start the Flutter web debug server (port 8888)
cd packages/client
flutter run -d web-server --web-port=8888 \
  --dart-define=SERVER_NAME=http://localhost:8888 \
  --dart-define=WS_SERVER_NAME=http://localhost:2080 \
  --dart-define=IMAGE_SERVER=http://localhost:9000/tentura
```

Open <http://localhost:8888> in a browser.

## Architecture Overview

```
Browser :8888  ──proxy──▶  Tentura API :2080  ──▶  Postgres :5432  ◀──▶  MeritRank (internal)
                  │
                  └──proxy──▶  Hasura :8080  ──▶  Postgres :5432

MinIO :9000 (S3-compatible object storage, console at :9001)
pgAdmin (Postgres UI, host-networked)
```

The Flutter dev server on `:8888` reverse-proxies API requests to the
backend services (configured in `packages/client/web_dev_config.yaml`):

| Path prefix               | Target                      |
|----------------------------|-----------------------------|
| `/api/v2/graphql`          | Tentura API `:2080`         |
| `/api/v2/ws`               | Tentura API `:2080` (WS)    |
| `/api/v1/graphql`          | Hasura `:8080` → `/v1/graphql` |
| `/shared/`                 | Tentura API `:2080`         |
| `/firebase-messaging-sw.js`| Tentura API `:2080`        |

## Port Map

| Port  | Service               |
|-------|-----------------------|
| 2080  | Tentura API (Dart)    |
| 5432  | PostgreSQL            |
| 8080  | Hasura GraphQL Engine |
| 8888  | Flutter web dev server|
| 9000  | MinIO S3 API          |
| 9001  | MinIO Console         |

## Detailed Steps

### 1. Environment File

Copy `.env.example` to `.env`. The defaults work out of the box for local
development (test JWT keys, `NEED_INVITE=false`, debug mode on).

### 2. Docker Compose

```bash
docker compose up -d          # start all services
docker compose down            # stop all services
docker compose logs -f postgres  # tail a specific service
```

`compose.yaml` includes `compose.dev.yaml` which runs Postgres, MeritRank,
Hasura, MinIO, and pgAdmin. All services except MeritRank use
`network_mode: host` so they bind directly to `localhost`.

Wait for Postgres to become healthy before proceeding (Hasura depends on it):

```bash
docker compose ps   # STATE should show "healthy" for postgres
```

### 3. Tentura API Server

```bash
./scripts/run-server-local.sh
```

This script loads `.env`, checks that port 2080 is free, and runs
`dart run bin/tentura.dart` inside `packages/server`. It runs in the
**foreground** — Ctrl+C stops it.

Successful startup prints:

```
Worker #0 web server listen [0.0.0.0:2080]
```

### 4. Flutter Web Debug Server

```bash
cd packages/client
flutter run -d web-server --web-port=8888 \
  --dart-define=SERVER_NAME=http://localhost:8888 \
  --dart-define=WS_SERVER_NAME=http://localhost:2080 \
  --dart-define=IMAGE_SERVER=http://localhost:9000/tentura
```

Key points:

- Uses the **web-server** device so it serves HTTP without launching a
  browser window.
- `SERVER_NAME=http://localhost:8888` makes the app send API requests to
  the dev server origin, which proxies them to the backend.
- `WS_SERVER_NAME=http://localhost:2080` tells the WebSocket client to
  connect directly to the API (the Flutter dev server cannot proxy WS).
- Hot reload is available via `r` in the terminal.
- First compilation takes ~30 seconds; subsequent hot reloads are fast.

**Important:** Do not launch via `nohup` or `&` with stdio redirection —
this breaks the Dart Development Service WebSocket and causes the process
to crash.

### Alternative: Chrome Device

For full DevTools integration (breakpoints, inspector):

```bash
cd packages/client
flutter run -d chrome --web-port=8888 \
  --dart-define=SERVER_NAME=http://localhost:8888 \
  --dart-define=WS_SERVER_NAME=http://localhost:2080 \
  --dart-define=IMAGE_SERVER=http://localhost:9000/tentura
```

## Codegen

After modifying GraphQL queries, Freezed entities, Drift tables, Auto Route
screens, or Injectable annotations:

```bash
dart run build_runner build -d   # -d deletes conflicting outputs
```

For localization changes (`.arb` files in `l10n/`):

```bash
flutter gen-l10n
```

## Hasura

- Console: <http://localhost:8080/console> (admin secret: `password`)
- To fetch the GraphQL schema into the client:

  ```bash
  docker compose run --rm schema_fetcher
  ```

## MinIO

- Console: <http://localhost:9001> (user: `minioadmin`, password: `minioadmin`)
- S3 API: <http://localhost:9000>
- Bucket: `tentura`

## pgAdmin

- <http://localhost:5050> (email: `admin@local.host`, password: `password`)
- Server mode is disabled; connects to Postgres automatically.

## Restarting Everything

```bash
# Full restart
docker compose down && docker compose up -d

# Kill and restart the API server
pkill -f 'bin/tentura\.dart'
./scripts/run-server-local.sh

# Kill and restart the web dev server
fuser -k 8888/tcp
cd packages/client && flutter run -d web-server --web-port=8888 \
  --dart-define=SERVER_NAME=http://localhost:8888 \
  --dart-define=WS_SERVER_NAME=http://localhost:2080 \
  --dart-define=IMAGE_SERVER=http://localhost:9000/tentura
```

## Cursor IDE / Agentic Development Notes

When using the Cursor IDE browser MCP to interact with the Flutter web app:

- **Buttons and navigation** work normally via `browser_click`.
- **Text input does not work** with CanvasKit (the default web renderer).
  Flutter renders on a `<canvas>` element; DOM-level `fill`/`type` calls
  update a hidden input but Flutter's framework never reads them. This is a
  known Flutter web limitation with all browser automation tools.
- For tasks that require text input (e.g., creating a user), use the
  API directly or a Dart test script.

## Monorepo Structure

```
tentura/
├── lib/                     # Shared domain (root package: tentura_root)
├── packages/
│   ├── client/              # Flutter app (mobile + web)
│   ├── server/              # Dart API server
│   └── widgetbook/          # Component catalogue
├── compose.yaml             # Default: includes compose.dev.yaml
├── compose.dev.yaml         # Local dev services
├── compose.prod.yaml        # Production (Tentura in Docker + Caddy)
├── hasura/                  # Hasura metadata and schema SQL
├── l10n/                    # Localization .arb files
└── scripts/                 # Helper scripts
```
