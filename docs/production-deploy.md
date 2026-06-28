# Tentura Production Deploy — Step by Step

## Prerequisites (on the DO droplet)

```bash
# Install Docker + Compose v2
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # log out and back in
docker compose version          # must say v2+
```

---

## 1. Create deployment directory and copy config files

```bash
sudo mkdir -p /srv/tentura_server
sudo chown $USER:$USER /srv/tentura_server
cd /srv/tentura_server
```

Copy these files from your local repo to the server:

```bash
scp compose.prod.yaml Caddyfile deploy.sh root@YOUR_SERVER:/srv/tentura_server/
ssh root@YOUR_SERVER "chmod +x /srv/tentura_server/deploy.sh"
```

---

## 2. Generate JWT Ed25519 key pair

```bash
openssl genpkey -algorithm ed25519 -out jwt_private.pem
openssl pkey -in jwt_private.pem -pubout -out jwt_public.pem
```

Format them as single-line with `\n` escapes (required by `.env`):

```bash
awk 'NR==1{printf "%s",$0} NR>1{printf "\\n%s",$0} END{print ""}' jwt_private.pem
awk 'NR==1{printf "%s",$0} NR>1{printf "\\n%s",$0} END{print ""}' jwt_public.pem
```

---

## 3. Set up external services (once)

| Service | What for | Key vars |
|---|---|---|
| **DigitalOcean Spaces** (or any S3) | Image/file storage | `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET` |
| **Resend** | Email magic-link auth | `RESEND_API_KEY`, `RESEND_FROM_EMAIL` |
| **Google Cloud** | OAuth login | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` |
| **Firebase** | Push notifications (FCM) | `FB_PROJECT_ID`, `FB_CLIENT_EMAIL`, `FB_PRIVATE_KEY`, etc. |
| **Sentry** | Error monitoring (server + client) | Two projects: `server` and `client` (landing is a third, separate) |

- **DO Spaces**: create a Space, generate an access key pair under API → Spaces Keys. Endpoint is `<region>.digitaloceanspaces.com`. Use `S3_PATH_STYLE=false` and `S3_USE_SSL=true` (unlike local MinIO defaults).
- **Google OAuth**: in Google Cloud Console add `https://YOUR_DOMAIN/api/auth/google/callback` as an authorized redirect URI.
- **Firebase**: create a service account, download the JSON, extract `project_id`, `client_email`, and `private_key` from it.
- **Sentry**: create two projects — one for the server (Dart/Other), one for the client (Flutter). Copy the DSN from each project's Settings → Client Keys. The server DSN goes in `.env`; the client DSN is compiled into the web build as a `--dart-define` (it is a public value, safe to embed). `SENTRY_RELEASE` and `SENTRY_DIST` are baked into the server image by CI automatically; you only need to configure the DSN and optionally the sample rate.

---

## 4. Create `.env` on the server

```bash
cd /srv/tentura_server
cat > .env << 'EOF'
# === POSTGRES ===
POSTGRES_PASSWORD=<strong-random-password>
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DBNAME=postgres
POSTGRES_USERNAME=postgres
POSTGRES_MAXCONN=20

# === JWT (Ed25519 PEM — use \n line escapes from step 2) ===
JWT_PUBLIC_PEM=-----BEGIN PUBLIC KEY-----\nMC...==\n-----END PUBLIC KEY-----\n
JWT_PRIVATE_PEM=-----BEGIN PRIVATE KEY-----\nMC...==\n-----END PRIVATE KEY-----\n
JWT_EXPIRES_IN=86400

# === CADDY / proxy ===
SERVER_NAME=dev.tentura.io          # no scheme, just hostname
APP_ROOT=/srv/web
LANDING_ROOT=/srv/landing
ACME_EMAIL=cert@yourdomain.com
CLIENT_MAX_BODY_SIZE=20MB
CORS=https://dev.tentura.io

# === HASURA ===
HASURA_GRAPHQL_ADMIN_SECRET=<strong-random-secret>
HASURA_GRAPHQL_CORS_DOMAIN=https://dev.tentura.io

# === TENTURA server ===
ENVIRONMENT=production
LOG_LEVEL=warn
WORKERS_COUNT=4
NEED_INVITE=false
DEBUG_MODE=false
IMAGE_SERVER=https://YOUR_SPACE.fra1.digitaloceanspaces.com/tentura
SESSION_EXPIRES_IN=2592000
MIN_CLIENT_VERSION=4.0.0

# === S3 (DO Spaces) ===
S3_ENDPOINT=fra1.digitaloceanspaces.com   # host only, no scheme
S3_BUCKET=tentura
S3_ACCESS_KEY=<spaces-access-key>
S3_SECRET_KEY=<spaces-secret-key>
S3_PATH_STYLE=false
S3_USE_SSL=true
# S3_OBJECT_ACL=omit   # uncomment if using a bucket policy for public reads

# === EMAIL (Resend) ===
RESEND_API_KEY=re_...
RESEND_FROM_EMAIL=Tentura <auth@yourdomain.com>

# === GOOGLE OAUTH ===
GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-...
OAUTH_PRELOAD_ENABLED=true

# === FIREBASE FCM (server push) ===
FB_PROJECT_ID=your-firebase-project
FB_CLIENT_EMAIL=firebase-adminsdk-xxx@your-firebase-project.iam.gserviceaccount.com
FB_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n
FB_SENDER_ID=123456789
FB_AUTH_DOMAIN=your-firebase-project.firebaseapp.com
FB_STORAGE_BUCKET=your-firebase-project.appspot.com
FB_API_KEY=AIza...
FB_APP_ID=1:123456789:web:abc...   # Web App ID from Firebase console, NOT the API key

# === SENTRY (server) ===
# DSN from Sentry project Settings → Client Keys (the "server" project, not "client").
# When unset, Sentry is fully disabled — no overhead.
# SENTRY_RELEASE and SENTRY_DIST are baked into the image by CI; do not set them here.
SERVER_SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz
SENTRY_TRACES_SAMPLE_RATE=1.0   # reduce (e.g. 0.1) once traffic grows
EOF

chmod 600 .env
```

---

## 5. (Optional) Create `compose.override.yaml`

For per-host structural overrides. Copy the example and edit:

```bash
# from local dev machine
scp examples/compose.override.example.yaml root@YOUR_SERVER:/srv/tentura_server/compose.override.yaml
```

Minimum useful production override:

```yaml
# /srv/tentura_server/compose.override.yaml
services:
  proxy:
    environment:
      - "SERVER_NAME=dev.tentura.io"
      - "APP_ROOT=/srv/web"
      - "LANDING_ROOT=/srv/landing"
      - ACME_EMAIL

  postgres:
    command: >-
      postgres
      -c max_connections=200
      -c shared_buffers=256MB

  tentura:
    image: ghcr.io/intersubjective/tentura:latest
    environment:
      - "SERVER_NAME=https://dev.tentura.io"   # full URL with scheme for the Tentura container
      - NEED_INVITE
      - POSTGRES_MAXCONN
```

---

## 6. First deploy — start the stack

```bash
cd /srv/tentura_server
mkdir -p web landing pg_data

docker compose -f compose.prod.yaml -f compose.override.yaml pull
docker compose -f compose.prod.yaml -f compose.override.yaml up -d

# Watch logs until stable
docker compose -f compose.prod.yaml logs -f
```

Wait until Postgres logs `database system is ready to accept connections` and Tentura logs `Worker #0 web server listen`.

The Tentura server runs all 104 SQL migrations on startup. This creates the full schema, all triggers, and all functions. **Do not apply `sql/triggers.sql` manually** — everything in it is already inside the migrations.

---

## 7. Apply Hasura metadata

Run once after first start (and after any schema changes):

```bash
# from local dev machine
HASURA_URL=https://dev.tentura.io/api/v1 \
HASURA_GRAPHQL_ADMIN_SECRET=<your-admin-secret> \
bash scripts/hasura_apply_metadata.sh
```

---

## 9. Deploy the Flutter web client (first time / manual)

Build locally, then upload:

```bash
# Get the client semver for SENTRY_RELEASE
CLIENT_VERSION=$(grep '^version:' packages/client/pubspec.yaml | sed 's/version:[[:space:]]*//' | sed 's/+.*//')
GIT_SHA=$(git rev-parse HEAD)

cd packages/client
flutter build web --wasm \
  --dart-define=SERVER_NAME=https://dev.tentura.io \
  --dart-define=IMAGE_SERVER=https://YOUR_SPACE.fra1.digitaloceanspaces.com/tentura \
  --dart-define=FB_APP_ID=1:123456789:web:abc... \
  --dart-define=FB_API_KEY=AIza... \
  --dart-define=FB_SENDER_ID=123456789 \
  --dart-define=FB_PROJECT_ID=your-firebase-project \
  --dart-define=FB_AUTH_DOMAIN=your-firebase-project.firebaseapp.com \
  --dart-define=FB_STORAGE_BUCKET=your-firebase-project.appspot.com \
  --dart-define=FB_VAPID_KEY=<your-vapid-key> \
  --dart-define=SENTRY_DSN=https://xxx@oyyy.ingest.sentry.io/zzz \
  --dart-define=SENTRY_ENVIRONMENT=prod \
  --dart-define="SENTRY_RELEASE=tentura@${CLIENT_VERSION}" \
  --dart-define="SENTRY_DIST=${GIT_SHA}"
# Omit the SENTRY_DSN line entirely to disable client Sentry (not an empty string — omit it).

cd ../..
tar -czf /tmp/web-$(date +%Y%m%d).tar.gz -C packages/client/build/web .
scp /tmp/web-*.tar.gz root@YOUR_SERVER:/tmp/
```

Then on the server:

```bash
cd /srv/tentura_server
OVERRIDE_FILE=compose.override.yaml ./deploy.sh /tmp/web-*.tar.gz
```

---

## 10. Wire up GitHub Actions CI/CD

Under **Settings → Environments** in your GitHub repo, create two environments — `dev` (triggered by pushes to `main`) and `prod` (triggered by pushes to `release`) — each with:

| Secret / Variable | Value |
|---|---|
| Secret `VPS_HOST` | server IP or hostname |
| Secret `VPS_SSH_KEY` | private SSH key for the deploy user |
| Secret `CLIENT_DART_DEFINES` | Firebase-only `KEY=VALUE` blob — see format below |
| Variable `CLIENT_SERVER_NAME` | `https://dev.tentura.io` (dev) / `https://tentura.io` (prod) |
| Variable `IMAGE_SERVER` | `https://YOUR_SPACE.fra1.digitaloceanspaces.com/tentura` |
| Variable `CLIENT_SENTRY_DSN` | DSN from the **client** Sentry project; omit to disable client Sentry |
| Variable `LANDING_SENTRY_DSN` | DSN from the **landing** Sentry project; omit to disable landing Sentry |
| Variable `LANDING_GOOGLE_ENABLED` | `true` or `false` |

All Sentry DSNs are public values — they end up compiled into client-side WASM/JS that any user can inspect, so plain variables (not secrets) are correct.

CI also passes `SENTRY_ENVIRONMENT` (`dev` or `prod`), `SENTRY_RELEASE=tentura@<semver>`, and `SENTRY_DIST=<git-sha>` automatically on every build. The server's `SERVER_SENTRY_DSN` is set in the VPS `.env` and is not a CI secret.

### `CLIENT_DART_DEFINES` format

This secret contains **only Firebase (`FB_*`) keys**. Do not put `SERVER_NAME`, `IMAGE_SERVER`, or Sentry values here — those are injected separately by the pipeline via individual `--dart-define` flags and would conflict.

Paste a plain multiline `KEY=VALUE` block into the secret textarea — one key per line, no quotes, no trailing spaces:

```
FB_APP_ID=1:123456789:web:abcdef123456
FB_API_KEY=AIzaSy...
FB_PROJECT_ID=your-firebase-project
FB_AUTH_DOMAIN=your-firebase-project.firebaseapp.com
FB_STORAGE_BUCKET=your-firebase-project.appspot.com
FB_SENDER_ID=123456789
FB_VAPID_KEY=BNmB...
```

All values come from Firebase Console → Project Settings:
- **`FB_APP_ID`** — Web App ID under "Your apps" (`1:…:web:…`). This is **not** the API key. Wrong value causes `firebaseinstallations` HTTP 400 in the browser.
- **`FB_VAPID_KEY`** — Web Push certificate key under Cloud Messaging → Web Push certificates.
- The rest come from the Firebase SDK config snippet.

GitHub preserves newlines in multiline secrets, so paste the block as-is. CI writes it to a file and passes it to `flutter build web --dart-define-from-file`.

Push to `main` → deploys to `dev`. Push to `release` → deploys to `prod`.

---

## 11. Verify

```bash
# All containers running
docker compose -f compose.prod.yaml ps

# TLS cert provisioned (give Caddy ~60s on first start)
curl -I https://dev.tentura.io

# Hasura health
curl https://dev.tentura.io/api/v1/graphql \
  -H "Content-Type: application/json" -d '{"query":"{__typename}"}'

# Tentura API health
curl https://dev.tentura.io/api/v2/graphql \
  -H "Content-Type: application/json" -d '{"query":"{__typename}"}'
```

---

## Common pitfalls

- **`SERVER_NAME` is used twice with different values.** Caddy gets the bare hostname (`dev.tentura.io`); the Tentura container gets the full URL with scheme (`https://dev.tentura.io`). Both must be set correctly.
- **`FB_APP_ID` must be the Firebase Web App ID** (`1:xxx:web:yyy` from Project settings → Your apps), not the API key (`AIza...`). Wrong value causes `firebaseinstallations` HTTP 400 in the browser.
- **`S3_PATH_STYLE=false` + `S3_USE_SSL=true`** for DO Spaces — opposite of local MinIO defaults.
- **Postgres data** lives in `./pg_data`. Back it up before any major upgrade.
- **Caddy TLS** auto-provisions via ACME on first start. Port 80 must be open for the HTTP-01 challenge.
- **After `.env` changes**, recreate only the affected container: `docker compose -f compose.prod.yaml up -d --force-recreate tentura`.
- **Hasura remote schema cache**: if you redeploy the server with changed GraphQL mutations, reload the remote schema: `curl -X POST http://hasura:8080/v1/metadata -H "X-Hasura-Admin-Secret: $SECRET" -d '{"type":"reload_remote_schema","args":{"name":"tentura"}}'`.
