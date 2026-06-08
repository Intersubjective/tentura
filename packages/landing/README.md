# @tentura/landing

Static invite/auth landing on the **same public origin** as the WASM app
(**tentura.io**, **dev.tentura.io**, local **dev.lvh.me:9443**). **Plain static
HTML/CSS/JS, served as-is — no npm, no `node_modules`, no bundler, no build
step.** Deps-light: the only external script is the Sentry browser SDK loaded
from its CDN.

It exists so an invite click renders instantly (300–800ms TTI) in in-app
webviews, instead of waiting 3–6s+ for the Flutter WASM app to boot. It fetches
the JSON preview from the Dart server and renders one of five states.

## Files (all served directly)

| File                 | Role                                                        |
|----------------------|-------------------------------------------------------------|
| `index.html`         | markup; loads Sentry CDN, `config.js`, optional `config.local.js`, `main.js` |
| `config.js`          | runtime config template (`appBase: ''` — CI sed injects deploy URL) |
| `config.local.js`    | gitignored local overlay — run `./scripts/sync-landing-local-config.sh` |
| `resolve_app_base.js`| shared resolver; throws if `appBase` missing/invalid        |
| `main.js`            | entry ES module; renders invite states + signed-out `/`     |
| `invite_entry.js`    | manual invite link/code parsing for signed-out `/`            |
| `preview.js`  | fetches `GET /api/v2/invite/:code/preview`                  |
| `webview.js`  | in-app-webview detection / Android `intent://`              |
| `analytics.js`| funnel events via the CDN Sentry global                     |
| `handoff.js`  | builds the `#th=…` URL + redirects to the app (transport)   |
| `auth.js`     | device-seed signup + `startEmailMagicLink` → `POST /api/v2/auth/email/start` |
| `styles.css`  | styling                                                     |

`handoff-dev.html` is a **dev-only** harness (not part of the shipped flow) for
exercising the session handoff by hand — see "Session handoff" below.

The browser resolves the relative ES-module imports (`main.js` → `./preview.js`
etc.) natively — nothing is bundled.

## Runtime config (`config.js` + optional `config.local.js`, no build step)

```js
window.TENTURA = { sentryDsn: '', apiBase: '', appBase: '', googleEnabled: false };
```

| Key              | Meaning                                          | Default  |
|------------------|--------------------------------------------------|----------|
| `sentryDsn`      | Sentry DSN; empty = analytics no-op              | `''`     |
| `apiBase`        | Origin for the preview API; empty = same origin  | `''`     |
| `appBase`        | WASM app origin; empty = same host as landing (`location.origin`) | `''` |
| `googleEnabled`  | Show Google OAuth in Tier-1 login reveal (needs server `GOOGLE_*`)  | `false`  |

**CI/deploy:** set GitHub Environment variable `LANDING_GOOGLE_ENABLED=true` when
server Google OAuth is configured; the pipeline injects it into `config.js`.
Local dev: `./scripts/sync-landing-local-config.sh` sets `googleEnabled` from
`GOOGLE_CLIENT_ID` in repo-root `.env`.

`resolve_app_base.js` uses `appBase` when set; otherwise it defaults to `location.origin/` (single-origin deploy). Invalid URLs still throw.

**Local dev:** copy repo-root `.env.example` → `.env`, then:

```bash
./scripts/sync-landing-local-config.sh   # writes config.local.js from APP_ORIGIN
./scripts/validate_landing_config.sh --local
```

**CI/deploy:** `pipeline.yml` sed-injects `appBase` from resolved `APP_BASE`; `validate_landing_config.sh` fails the job if still empty.

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
  entry (paste link/code → `/invite/:code`), and “I already have an account” which
  reveals tier-specific login options (Tier 1: email + Google; Tier 2: email +
  browser escape). No generic “Open Tentura” for anonymous visitors.
- **Invite URL:** `/invite/:code` (e.g. `https://dev.tentura.io/invite/I…`).
- Renders 5 preview states from `suggestedAction`: invalid · is-inviter ·
  already-friends · existing-user (befriend) · anonymous (login reveal + Tier-1 signup).
- **Beacon overlay** shown above the CTA in every state when `beacon` is present.
- Funnel events fire via Sentry **before** any WASM.

## Auth

- **Email magic link (Tier 1 + 2):** `startEmailMagicLink()` →
  `POST /api/v2/auth/email/start`. Verify sets `__Host-tentura_session` and
  redirects to `/invite/:code?signed_in=1`. Requires server `RESEND_*` env.
- **Google OAuth (Tier 1 only):** `ctaGoogleSignIn()` inside the “I already have an
  account” login reveal when `googleEnabled` and not `env.inApp` →
  `/api/auth/google/start`. Sets session cookie on callback.
- **Device-seed signup (Tier 1 only):** `signUpWithSeed()` uses native WebCrypto
  Ed25519, POSTs `accept-as-new`, then `#th=` handoff via `handoff.js`.
  `AUTH_ENABLED` in `main.js` is the kill-switch. Never offered in Tier-2
  webviews (ephemeral storage would lose the key).
- **Secure context required** for device-seed (`crypto.subtle`). Local E2E needs
  HTTPS (e.g. `dev.lvh.me:9443`).
- **Tier-2 escape:** Android `intent://`, iOS copy-link + Safari coaching.
- **Deferred:** passkey/Apple; link Google/email from Settings; per-IP signup
  rate-limiting beyond email-auth limits.
- Session handoff (`#th=`) contract: `docs/handoff-contract.md` (device-seed
  only — email/Google use the session cookie).

### Seed encoding (do not break)

The seed string in the handoff payload must be url-safe base64 **with `=`
padding** — the app decodes it with `base64Decode` (no normalize), which throws
on un-padded input. `auth.js` has its own padded helper; do **not** reuse
`handoff.js`'s `base64url()` (it strips padding — correct for the fragment, fatal
for the seed). The auth-request JWT segments use JWT-standard base64url *without*
padding.

## Session handoff (device-seed → WASM app)

On single-origin deploy, landing and WASM share `location.origin` (`appBase`
defaults empty). **Only device-seed signup** uses `#th=` handoff — email and
Google set the HttpOnly session cookie instead.

`handoff.js` redirects with `{ userId, seed }` in the URL fragment
(`{appBase}#th=<base64url(utf8(json))>`); WASM captures it before boot, writes
secure storage, and scrubs the fragment. Field names are pinned in
`docs/handoff-contract.md` (`scripts/check_handoff_contract.sh` in CI).

`redirectToApp({ userId, seed, displayName? })` is the transport entry;
`signUpWithSeed(...)` produces the payload. Dev harness: `handoff-dev.html`.
