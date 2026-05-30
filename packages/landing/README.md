# @tentura/landing

Static invite/auth landing for **tentura.io** / **dev.tentura.io** (WASM app on
**app.tentura.io** / **app.dev.tentura.io**). **Plain static HTML/CSS/JS, served as-is — no npm, no
`node_modules`, no bundler, no build step.** Deps-light: the only external
script is the Sentry browser SDK loaded from its CDN.

It exists so an invite click renders instantly (300–800ms TTI) in in-app
webviews, instead of waiting 3–6s+ for the Flutter WASM app to boot. It fetches
the JSON preview from the Dart server and renders one of five states.

## Files (all served directly)

| File          | Role                                                        |
|---------------|-------------------------------------------------------------|
| `index.html`  | markup; loads Sentry CDN, `config.js`, then `main.js`       |
| `config.js`   | runtime config (no build injects values) — see below       |
| `main.js`     | entry ES module; renders the 5 states + beacon overlay      |
| `preview.js`  | fetches `GET /api/v2/invite/:code/preview`                  |
| `webview.js`  | in-app-webview detection / Android `intent://`              |
| `analytics.js`| funnel events via the CDN Sentry global                     |
| `handoff.js`  | builds the `#th=…` URL + redirects to the app (transport)   |
| `styles.css`  | styling                                                     |

`handoff-dev.html` is a **dev-only** harness (not part of the shipped flow) for
exercising the session handoff by hand — see "Session handoff" below.

The browser resolves the relative ES-module imports (`main.js` → `./preview.js`
etc.) natively — nothing is bundled.

## Runtime config (`config.js`, no build step)

```js
window.TENTURA = { sentryDsn: '', apiBase: '', appBase: 'https://app.dev.tentura.io/' };
```

| Key         | Meaning                                          | Default  |
|-------------|--------------------------------------------------|----------|
| `sentryDsn` | Sentry DSN; empty = analytics no-op              | `''`     |
| `apiBase`   | Origin for the preview API; empty = same origin  | `''`     |
| `appBase`   | Absolute WASM-app origin (subdomain)             | `https://app.dev.tentura.io/` |

Edit `config.js` per-deploy, or substitute its values at deploy time.

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

- URL scheme: `/invite/:code` on the landing host (e.g. `https://dev.tentura.io/invite/I…`)
  (link compatibility, Risk #7).
- Renders 5 states from `suggestedAction`: invalid · is-inviter ·
  already-friends · existing-user (befriend) · anonymous (3 ordered CTAs).
- **Beacon overlay** shown above the CTA in every state when `beacon` is present.
- Funnel events fire via Sentry **before** any WASM.

## Phase 0 scope / not yet wired

- Auth CTAs (passkey/Google/Apple/email) are **feature-flagged off**
  (`AUTH_ENABLED = false` in `main.js`) — real auth is **Phase 1**.
- Tier-2 (in-app webview) browser escape: Android `intent://`, iOS copy-link +
  Safari coaching (no programmatic iOS escape, Risk #2).
- Ed25519 (Phase 1) will be loaded **in-browser** (CDN ESM or a vendored single
  file), never via npm.
- Session handoff key names are pinned in `docs/handoff-contract.md`.

## Session handoff (landing → WASM app)

Landing and app are different origins, so localStorage is not shared. After auth,
`handoff.js` redirects to the app with the account `{ userId, seed }` in the URL
**fragment** (`{appBase}#th=<base64url(utf8(json))>`); the WASM app captures it
before boot, writes it to its own secure storage, and scrubs it. The fragment
never reaches the server. Field names (`th`, `v`, `userId`, `seed`,
`displayName`) are the contract in `docs/handoff-contract.md`, pinned across both
sides by `scripts/check_handoff_contract.sh` (CI).

`redirectToApp({ userId, seed, displayName? })` is the transport entry point; the
real auth that produces the seed lands in a later slice. To exercise it now, serve
the landing locally and open `handoff-dev.html`, paste a known `userId` + `seed`,
and click through — the app should boot already signed in.
