# @tentura/landing

Static invite/auth landing on the **same public origin** as the WASM app
(**tentura.io**, **dev.tentura.io**, local **dev.lvh.me:9443**). **Plain static
HTML/CSS/JS, served as-is — no npm, no `node_modules`, no bundler, no build
step.** Deps-light: the only external script is the Sentry browser SDK loaded
from its CDN.

It exists so an invite click renders instantly (300–800ms TTI) in in-app
webviews, instead of waiting 3–6s+ for the Flutter WASM app to boot. It fetches
the JSON preview from the Dart server and renders one of five states.

On load, the landing also starts **background WASM asset warmup** (service worker
registration + Cache Storage population) so the app boots faster when the user
opens it — gated off in in-app webviews, Save-Data mode, and slow links.

## Files (all served directly)

| File                 | Role                                                        |
|----------------------|-------------------------------------------------------------|
| `index.html`         | markup; loads Sentry CDN, `config.js`, optional `config.local.js`, `main.js` |
| `config.js`          | runtime config template (`apiBase`, `googleEnabled`, `sentryDsn`) |
| `config.local.js`    | no-op stub by default; `./scripts/sync-landing-local-config.sh` sets `googleEnabled` locally |
| `main.js`            | entry ES module; renders invite states + signed-out `/`     |
| `app_preload.js`     | background WASM asset warmup (manifest + SW + cache)        |
| `invite_entry.js`    | manual invite link/code parsing for signed-out `/`            |
| `preview.js`  | fetches `GET /api/v2/invite/:code/preview`                  |
| `webview.js`  | in-app-webview detection / Android `intent://`              |
| `analytics.js`| funnel events via the CDN Sentry global                     |
| `auth.js`     | `startEmailMagicLink` → `POST /api/v2/auth/email/start`     |
| `styles.css`  | styling                                                     |

The browser resolves the relative ES-module imports (`main.js` → `./preview.js`
etc.) natively — nothing is bundled.

## Runtime config (`config.js` + optional `config.local.js`, no build step)

```js
window.TENTURA = { sentryDsn: '', apiBase: '', googleEnabled: false };
```

| Key              | Meaning                                          | Default  |
|------------------|--------------------------------------------------|----------|
| `sentryDsn`      | Sentry DSN; empty = analytics no-op              | `''`     |
| `apiBase`        | Origin for the preview API; empty = same origin  | `''`     |
| `googleEnabled`  | Show Google OAuth when not in-app (needs server `GOOGLE_*`)  | `false`  |

**CI/deploy:** set GitHub Environment variable `LANDING_GOOGLE_ENABLED=true` when
server Google OAuth is configured; the pipeline injects it into `config.js`.
Local dev: `./scripts/sync-landing-local-config.sh` sets `googleEnabled` from
`GOOGLE_CLIENT_ID` in repo-root `.env`.

**Local dev:** copy repo-root `.env.example` → `.env`, then:

```bash
./scripts/sync-landing-local-config.sh   # writes config.local.js (googleEnabled)
./scripts/resolve_local_web_config.sh --check-only
```

See also `config.local.example.js` for a manual template.

## Local preview

No toolchain needed — serve the directory with any static server, e.g.:

```bash
python3 -m http.server -d packages/landing 8080
```

## Deploy

CICD just **tars the static files** into `landing-*.tar.gz`; `deploy.sh`
extracts them to `./landing`, which `compose.prod.yaml` mounts at `/srv/landing`
(Caddy `{$LANDING_ROOT}`). No Node/npm in the pipeline.

## Routes / states

- **Signed-out `/`:** `renderNoInvite()` — invite-only explanation, manual invite
  entry (paste link/code → `/invite/:code`), email OTP, Google (Tier 1), and
  seed recovery link. No generic “Open Tentura” for anonymous visitors.
- **Invite URL:** `/invite/:code` (e.g. `https://dev.tentura.io/invite/I…`).
- Renders 5 preview states from `suggestedAction`: invalid · is-inviter ·
  already-friends · existing-user (befriend) · anonymous (email/Google/recover).
- **Beacon overlay** shown above the CTA in every state when `beacon` is present.
- Funnel events fire via Sentry **before** any WASM boot; app asset warmup starts
  immediately in the background (see `app_preload.js`).

## WASM background warmup

`app_preload.js` runs on every landing visit (fire-and-forget from `main.js`):

- Registers `/tentura-app-cache-sw.js` and fetches `/wasm-preload-manifest.json`.
- Populates `tentura-app-assets-<version>` in Cache Storage (same contract as the
  OAuth warmup interstitial and the WASM app's own service worker).
- Uses low-priority / idle scheduling so the invite preview JSON is not delayed.
- **Skipped** when: Tier-2 in-app webview (`env.inApp`), Save-Data is on, or
  `navigator.connection.effectiveType` is `slow-2g` / `2g`.

## Auth

- **Email magic link (Tier 1 + 2):** `startEmailMagicLink({ email, code })` →
  `POST /api/v2/auth/email/start` with optional `inviteCode`. Verify sets
  `__Host-tentura_session`, accepts the invite when appropriate, and redirects to
  `/invite/:code?signed_in=1`. Requires server `RESEND_*` env.
- **Google OAuth (Tier 1 only):** `ctaGoogleSignIn(code)` when `googleEnabled` and
  not `env.inApp` → `/api/auth/google/start?invite=…&returnTo=…`. Sets session
  cookie on callback and returns to the invite page.
- **Seed recovery (returning users):** `appRecoverUrl(code)` →
  `/recover?invite=<code>#/recover-seed`. Seed is entered **inside WASM only**;
  after sign-in the app navigates to `#/accept-invite/<code>`. Not offered in
  Tier-2 webviews (use browser escape first).
- **Tier-2 escape:** Android `intent://`, iOS copy-link + Safari coaching.
- **Deferred:** passkey/Apple; link Google/email from Settings.

Device-seed **signup on the landing** and `#th=` URL handoff were removed; see
`docs/handoff-contract.md` (retired).
