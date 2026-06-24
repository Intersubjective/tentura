# CI/CD Setup Guide

## Overview

This project uses GitHub Actions for automated builds and deployments. The CI/CD pipeline supports three environments: dev, stage, and production.

## Workflows

### Build and Deploy (`build-and-deploy.yml`)

**Triggers:**
- Push to `dev` branch → builds and deploys to dev environment
- Push to `main` branch → builds and deploys to stage, then production (with approval)

**Stages:**
1. **Determine Target**: Extracts versions from `pubspec.yaml` files and determines build type
2. **Test**: Runs Dart and Flutter tests
3. **Build Server**: Builds Docker image and pushes to `ghcr.io/intersubjective/tentura-server`
4. **Build Web**: Builds Flutter web static files and creates `.tar.gz` archives
5. **Deploy Dev**: Deploys to dev environment (automatic)
6. **Deploy Stage**: Deploys to stage environment (automatic for main branch)
7. **Deploy Prod**: Deploys to production environment (requires manual approval)

### CI (`ci.yml`)

**Triggers:**
- Pull requests to `main` or `dev`
- Pushes to `main`

**Stages:**
1. **Test**: Runs Dart and Flutter tests
2. **Validate Builds**: Validates Docker and Flutter builds without pushing

## Required Secrets

Configure secrets under **Settings → Environments** (per environment) and **Settings → Secrets and variables → Actions** (repo-wide) as needed.

### `dev` environment (web build on push to `main`)

- `CLIENT_DART_DEFINES`: Multiline `.env` blob for Flutter `--dart-define-from-file` (Firebase client compile-time config). One secret instead of per-key vars. Example content (same keys as local `packages/client/env/dev-web.env`):

  ```
  FB_SENDER_ID=...
  FB_PROJECT_ID=...
  FB_AUTH_DOMAIN=...
  FB_STORAGE_BUCKET=...
  FB_API_KEY=...
  FB_APP_ID=...
  FB_VAPID_KEY=...
  ```

  **`FB_APP_ID` must be the Firebase Web App ID** from Project settings → Your apps (format `1:123456789:web:abc…`). **Do not** paste `FB_API_KEY` (`AIza…`) into `FB_APP_ID` — that causes `firebaseinstallations.googleapis.com` **400** in the browser.

  CI writes this to repo-root `.env` before `flutter build web` and runs `scripts/validate_client_firebase_env.sh`.

  **Deploy web config** (before every `build-web` on `main`): `scripts/resolve_deploy_web_config.sh` validates required vars and derives optional ones. The build **fails** if required values are missing or not absolute `http(s)://` URLs. Never pass empty `--dart-define=VAR=` (unset GitHub vars override Dart defaults).

  | GitHub `dev` variable | Required | Resolved value |
  |----------------------|----------|----------------|
  | `CLIENT_SERVER_NAME` | **Yes** | WASM `--dart-define=SERVER_NAME` and invite share links (`/invite/I…`) on the single public origin (e.g. `https://dev.tentura.io`) |
  | `IMAGE_SERVER` | **Yes** | WASM `--dart-define=IMAGE_SERVER` (CDN/S3 base for image URLs) |
  | `CLIENT_SENTRY_DSN` | **No** | WASM `--dart-define=SENTRY_DSN` for the **client** Sentry project DSN. Public value (not a secret). Omitted from the build when unset — never pass an empty `--dart-define=SENTRY_DSN=`. See [ADR 0006](../docs/adr/0006-client-sentry-observability.md). |

  CI also passes `--dart-define=SENTRY_ENVIRONMENT=dev`, `--dart-define=SENTRY_RELEASE=tentura@<client semver>`, and `--dart-define=SENTRY_DIST=<commit SHA>` on every web build.

  **Source-map upload (deferred):** when enabled, set secrets `SENTRY_AUTH_TOKEN` and variables `SENTRY_ORG`, `SENTRY_PROJECT` (`tentura-client`); run `dart run sentry_dart_plugin` post-build with matching release/dist. Not wired in CI while the deploy target uses `--wasm` (see ADR 0006).

  CI also passes `--dart-define=BUILD_GIT_SHA` (commit SHA, same as `WEB_BUILD_ID`) and `--dart-define=BUILD_DATE` (UTC `YYYY-MM-DD` at build time). These surface in **Settings** for build verification.

  Local check: `CLIENT_SERVER_NAME=https://dev.tentura.io IMAGE_SERVER=https://cdn.example/bucket bash scripts/resolve_deploy_web_config.sh --check-only`

  **Server vs client:** `FB_APP_ID` on the VPS (service worker via Tentura API) and in `CLIENT_DART_DEFINES` (compiled into the Flutter web app) must both be correct. Redeploying the API alone does not fix a bad web build — push to `main` must rebuild web after updating the secret.

  **Runtime (VPS, not web build):** `SERVER_NAME` on the Tentura container (OG `/shared/view` URLs) — set in VPS `.env`, separate from `CLIENT_SERVER_NAME`.

  **Server Sentry (VPS / `compose.prod.yaml`):**

  | Env var | Required | Purpose |
  |---------|----------|---------|
  | `SERVER_SENTRY_DSN` | **No** | DSN for the **server** Sentry project. When unset/empty, the SDK is not initialized. |
  | `SENTRY_TRACES_SAMPLE_RATE` | **No** | Request transaction sample rate (default `1.0`). |

  `SENTRY_RELEASE` and `SENTRY_DIST` are baked into the server image at CI build time (`tentura-server@<semver>` and git SHA). See [ADR 0007](../docs/adr/0007-server-sentry-observability.md).

### Per Environment (dev/stage/prod) — deploy

- `VPS_HOST`: Target server hostname or IP address
- `VPS_SSH_KEY`: SSH private key for deployment (must have access to deploy user)

### Shared

- `GITHUB_TOKEN`: Automatically provided by GitHub Actions (no setup needed)

## Environment Configuration

### Production Approval Gate

Production deployments require manual approval. To configure:

1. Go to **Settings > Environments**
2. Create or edit the `prod` environment
3. Under **Protection rules**, enable **Required reviewers**
4. Add repository owners or specific team members as reviewers

When a deployment to production is triggered, it will pause and wait for approval from a configured reviewer before proceeding.

## Docker Image Tagging

- **Dev branch**: Images tagged as `dev-{sha}` and `dev-latest`
- **Main branch**: Images tagged as `v{version}` and `latest`
- **Deployment**: Always uses `latest` tag in Docker Compose

## VPS Setup

### 1. Create Deployment Directory

```bash
sudo mkdir -p /opt/tentura
sudo chown deploy:deploy /opt/tentura
```

Or use user home directory:
```bash
mkdir -p ~/tentura
```

### 2. Install Deployment Script

Copy `examples/deploy.sh` to your VPS:

```bash
# On VPS
sudo cp examples/deploy.sh /opt/tentura/deploy.sh
sudo chmod +x /opt/tentura/deploy.sh
sudo chown deploy:deploy /opt/tentura/deploy.sh
```

### 3. Setup SSH Access

Ensure the SSH key used in GitHub secrets has:
- Access to the `deploy` user account
- Permissions to run Docker commands
- Access to the deployment directory

### 4. Docker Compose Setup

Ensure `compose.prod.yaml` is present in the deployment directory on the VPS.

The deployment script expects:
- `compose.prod.yaml` in the deployment directory
- `./web/` directory for static files (mounted in Docker Compose)

## Deployment Process

1. **Build**: Server Docker image and Flutter web static files are built
2. **Archive**: Web files are packaged into `.tar.gz` archives
3. **Transfer**: Archives are copied to VPS via SCP
4. **Extract**: Archives are extracted to the Docker volume mount point
5. **Update**: Docker Compose pulls latest images and restarts services

## Troubleshooting

### Build Failures

- Check that `packages/server/Dockerfile_build` references the correct entry point (`bin/tentura.dart`)
- Ensure all dependencies are properly configured in `pubspec.yaml` files

### Deployment Failures

- Verify SSH key has correct permissions and access
- Check that deployment directory exists and is writable
- Ensure Docker Compose is installed and accessible to the deploy user
- Verify `compose.prod.yaml` is present in the deployment directory

### Approval Not Working

- Ensure the `prod` environment is configured in GitHub repository settings
- Check that required reviewers are added to the environment
- Verify the workflow references the correct environment name (`prod`)

