---
name: local-debug
description: >
  Run and debug the full Tentura stack locally: docker compose infra
  (Postgres + MeritRank + Hasura + MinIO), tentura-server in a console
  (debug mode), Flutter web client in debug mode (no WASM compile), Caddy
  front proxy, and Playwright MCP driving the app. Covers the QA
  login/signup bypass (.env QA_* parameters), and direct API / Hasura /
  Postgres SQL access to set up state or trigger actions without the UI.
  Activate for any local e2e, QA-login, stack-health, or "reproduce this
  bug locally" work.
---

# Tentura local debug stack

Canonical entry point: **https://dev.lvh.me:9443** (Caddy, TLS internal;
`dev.lvh.me` resolves to 127.0.0.1). `__Host-` session cookies require this
HTTPS origin — don't test auth on plain `http://localhost:8888`.

## Components & ports

| Component | How it runs | Port |
|---|---|---|
| Postgres (`vbulavintsev/postgres-tentura`) | compose service | 127.0.0.1:5432 |
| MeritRank | compose service, **internal network only** (reached by Postgres via `tcp://meritrank:8080`) | — |
| Hasura | compose service, host network | 8080 |
| MinIO | compose service | 9000 (API) / 9001 (console) |
| pgAdmin | compose service | 5050 |
| tentura-server (Dart API) | **console, foreground**: `./scripts/run-server-local.sh` | 2080 |
| Flutter client (debug, dartdevc — no WASM) | `./scripts/run-flutter-web-local.sh` | 8888 |
| Caddy | `caddy run --config Caddyfile.local` | 9443 (HTTPS) / 9080 (HTTP smoke) |

Caddy routes: app paths → :8888 dev server (or `packages/client/build/web`
if `LOCAL_USE_FLUTTER_PROXY=off`), `/api/v1/graphql` → Hasura :8080,
API v2 / auth / QA / shared paths → :2080, landing = static
`packages/landing`.

## Startup order

```bash
docker compose up -d                       # postgres, meritrank, hasura, minio, pgadmin
docker compose ps                          # wait: postgres "healthy"
./scripts/run-server-local.sh              # terminal 1 — foreground, Ctrl+C stops
./scripts/run-flutter-web-local.sh         # terminal 2 — flutter run -d web-server :8888
caddy run --config Caddyfile.local         # terminal 3
```

Health checks: `curl -s http://127.0.0.1:2080/health` → `I\`m fine!`;
`curl -sk https://dev.lvh.me:9443/api/v2/graphql -o /dev/null -w '%{http_code}'`.

**Critical pitfalls:**

- **Never** run a bare `dart run bin/tentura.dart` — it uses compiled-in
  defaults: PORT=2081 (Caddy proxies to 2080 → 502), wrong SERVER_NAME
  (dead magic links), default JWT keys (Hasura rejects tokens with
  `JWSInvalidSignature`; v1 GraphQL returns HTTP 200 with an errors body and
  the app spins forever on My Work). Always use `scripts/run-server-local.sh`,
  which loads `.env` and validates it. Verify a running server:
  `tr '\0' '\n' < /proc/$(pgrep -f bin/tentura.dart)/environ | grep JWT` —
  empty = broken.
- **Never** background the server or flutter with `nohup`/`&` + stdio
  redirection — it kills the Dart Development Service WebSocket. Use separate
  terminals or `run_in_background` process management.
- Client debug mode = dartdevc hot-reload (`r` in the flutter terminal);
  no `flutter build web --wasm` needed. The WASM build + service-worker
  cache dance only applies to the `LOCAL_USE_FLUTTER_PROXY=off` static path.
- Restart recipes: `pkill -f 'bin/tentura\.dart'`, `fuser -k 8888/tcp`,
  `docker compose down && docker compose up -d`.

## QA parameters in `.env`

| Var | Meaning |
|---|---|
| `QA_AUTH_ENABLED=true` + `QA_AUTH_TOKEN` | enables secret-gated `GET /_qa/latest-email` and `POST /_qa/send-fcm`; captures magic links for QA domains |
| `QA_EMAIL_DOMAINS` | allowlist (`test.tentura.local,qa.tentura.local,example.test`) — QA endpoints only work for these |
| `EMAIL_DEBUG_SINK_DIR=.local/email-sink` | magic links written to `<dir>/<email>.json` instead of Resend (relative to `packages/server/`) |
| `QA_SIMPLE_LOGIN_MODE=true` | enables `POST /api/v2/auth/email/test-login` — instant sign-in, no magic link. Independent of `QA_AUTH_ENABLED`; **not set by default — add it and restart the server** |

Read the token from `.env` (`QA_AUTH_TOKEN`), **not** the stale `qa_token`
file at repo root. All QA routes are disabled when `ENVIRONMENT=prod`.

## Login / signup bypass (fastest first)

Signup and login are the same flow: an unknown QA email creates an account
(`NEED_INVITE=false` locally; pass `inviteCode` in the body to test invite
flows).

**1. Instant test-login** (needs `QA_SIMPLE_LOGIN_MODE=true`): from an
on-origin browser page (so the cookie lands in the browser), or curl with a
cookie jar:

```bash
curl -sk -c /tmp/qa.jar https://dev.lvh.me:9443/api/v2/auth/email/test-login \
  -H 'Content-Type: application/json' \
  -d '{"email":"someone@test.tentura.local"}'
# → {"ok":true,"immediate":true,"redirectUrl":...,"isNewAccount":...} + __Host-tentura_session cookie
```

In Playwright: navigate to `https://dev.lvh.me:9443` first, then `fetch()`
this endpoint from page context and reload — the session cookie is set.

**2. Magic-link via QA capture** (works with default `.env`):

```bash
curl -sk https://dev.lvh.me:9443/api/v2/auth/email/start \
  -H 'Content-Type: application/json' -d '{"email":"someone@test.tentura.local"}'
curl -s "http://127.0.0.1:2080/_qa/latest-email?email=someone@test.tentura.local&_qa_token=$QA_AUTH_TOKEN"
# → {"found":true,"verifyUrl":...}
```

Rewrite the `verifyUrl` host to `dev.lvh.me:9443` if needed and open it in
the browser → click "Continue to Tentura" (GET only peeks; the POST consumes
the token) → session cookie set. Headless equivalent:
`curl -sk -c /tmp/qa.jar -X POST https://dev.lvh.me:9443/auth/email/verify -d "t=<token>"`
(form-encoded; token = `t` query param of `verifyUrl`; responds 302 + cookie).

**3. Sink file directly:** `packages/server/.local/email-sink/<sanitized-email>.json`
contains `verifyUrl` — no QA endpoint needed.

Durable QA fixtures in the postgres volume: author
`agent-1782689243-19095@test.tentura.local` (`Ua6432bd9e599`, beacon
`B2332d32c0366`) and admitted helper `agent-b-…-29289` (`U67b543012fca`).
Bulk fake activity: `scripts/seed_society`.

## Direct API calls (set up state / trigger actions without the UI)

Exchange the session cookie for a JWT, then hit either GraphQL API as that
user:

```bash
JWT=$(curl -sk -b /tmp/qa.jar https://dev.lvh.me:9443/api/v2/session/access-token | jq -r .accessToken)
# Tentura API v2 (remote schema: mutations like beaconCreate, beaconClose…)
curl -sk https://dev.lvh.me:9443/api/v2/graphql -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' -d '{"query":"{ ... }"}'
# Hasura v1 as the user (row permissions apply)
curl -s http://127.0.0.1:8080/v1/graphql -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' -d '{"query":"{ ... }"}'
```

REST v2 endpoints (`/api/v2/...` in `packages/server/lib/api/root_router.dart`)
accept the same Bearer JWT; browser flows use the cookie.

## Local Hasura

- Console: <http://localhost:8080/console>, admin secret `password`.
- Admin GraphQL (bypasses permissions — good for state inspection/setup):
  `curl -s http://localhost:8080/v1/graphql -H 'x-hasura-admin-secret: password' ...`
  Add `-H 'x-hasura-role: user' -H 'x-hasura-user-id: U…'` to impersonate.
- `/api/v1/graphql` merges Postgres with the **Tentura remote schema**
  (server :2080). After changing Tentura-only mutation signatures, reload it
  or you get "has no argument named …":

  ```bash
  curl -sS -X POST http://localhost:8080/v1/metadata \
    -H "X-Hasura-Admin-Secret: password" -H "Content-Type: application/json" \
    -d '{"type":"reload_remote_schema","args":{"name":"tentura"}}'
  ```
- Metadata changes: `scripts/hasura_apply_metadata.sh`; schema fetch for the
  client: `docker compose run --rm schema_fetcher`.

## Direct Postgres SQL

```bash
docker exec -it postgres psql -U postgres            # or:
PGPASSWORD=password psql -h 127.0.0.1 -U postgres
```

Use this to seed rows, flip beacon/user state, or fire triggers that are slow
to reach via UI. Schema is owned by raw SQL migrations (not Drift). Caveat:
MeritRank scores are written via `trust_apply_evidence` / `user_trust_edge`
(m0088) — do **not** seed via the dropped `vote_user` path. Postgres talks to
MeritRank itself (`MERITRANK_SERVICE_URL=tcp://meritrank:8080`); if trust
functions hang, check `docker compose logs meritrank`.

## Playwright MCP driving

- Use the `mcp__playwright__*` tools against `https://dev.lvh.me:9443`.
- Enable Flutter semantics first: force-click `flt-semantics-placeholder`.
  Rail items expose accessible *text* ("My people Tab 3 of 4"); the compact
  bottom bar uses plain `aria-label` ("My people").
- **Text input via DOM `fill`/`type` does not work** (CanvasKit renders to a
  canvas). Type via `browser_press_key` after focusing, or better: set up the
  state via API/SQL (above) and use the UI only for the flow under test.
- Same-origin hash-only `page.goto` does **not** reload the app — bounce
  through `about:blank` for a cold start.
- Back-nav regression suite: `scripts/e2e_backnav/suite.js` via
  `browser_run_code_unsafe` (filename mode).
- A wedged MCP Chrome (expired TLS session → dead API) mimics app bugs —
  restart the browser before debugging "the app".
- Static-build path only: unregister service workers + `caches.delete(...)`
  after every rebuild (SW cache is profile-persisted, cache-first, fixed
  CACHE_VERSION) or you silently test the old bundle.

## Troubleshooting quick map

| Symptom | Cause / fix |
|---|---|
| 502 on `/api/v2/*` through Caddy | server on 2081 (bare `dart run`) — restart via `run-server-local.sh` |
| `JWSInvalidSignature` from Hasura / My Work spins forever | server with default JWT keys — same fix |
| magic link points at `localhost:8899` | server missing `.env` `SERVER_NAME` — same fix |
| `_qa/latest-email` 404 | `QA_AUTH_ENABLED`/token unset, wrong token (stale `qa_token` file), or non-QA email domain |
| `test-login` 404 | `QA_SIMPLE_LOGIN_MODE=true` missing from `.env` (then restart server) |
| Hasura "no argument named X" | stale remote schema — reload (see Hasura section) |
| ~1s splash reload boot-loop (static path) | JS-only build against WASM-expecting bootstrap/SW — rebuild with `--wasm`, clear SW + HTTP caches |
