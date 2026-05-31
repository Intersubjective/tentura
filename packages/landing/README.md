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
| `auth.js`     | device-seed signup: WebCrypto Ed25519 + auth-request JWT + accept-as-new |
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

## Auth (slice 3) — device-seed signup, Tier-1 only

- **Live:** anonymous device-seed signup. `auth.js` generates an Ed25519 keypair
  with **native WebCrypto** (`crypto.subtle`, no npm, no vendored lib), self-signs
  an EdDSA auth-request JWT, and POSTs `accept-as-new`; on success it hands the
  **seed** to the app via `handoff.js`. `AUTH_ENABLED` (in `main.js`) is the
  master kill-switch.
- **Secure context required.** `crypto.subtle` exists only in a secure context
  (HTTPS, or a `localhost`/`127.0.0.1` host). Over plain `http://dev.lvh.me:9080`
  it is absent, so the signup CTA is hidden (feature-detect returns false) — local
  signup E2E needs HTTPS or a `localhost`-named host; the dev stack is HTTPS.
- **Tier-1 only.** Signup is offered **only** in system browsers with native
  WebCrypto Ed25519. It is deliberately **never** offered in Tier-2 in-app
  webviews: a device key minted in an ephemeral/siloed webview would be lost when
  the webview closes (and is unrecoverable without a second credential). Tier-2
  keeps the "open in your browser" escape; the **email** path (recoverable) is
  the eventual Tier-2 method — a later slice.
- **Deferred:** passkey/Google/Apple/email providers (need their server providers,
  deferred in slice 2); per-IP signup rate-limiting (invite slots are the interim
  limiter); befriend-on-open for existing accounts (slice-4 client work — here
  "I already have an account" just opens the app).
- Tier-2 (in-app webview) browser escape: Android `intent://`, iOS copy-link +
  Safari coaching (no programmatic iOS escape, Risk #2).
- Session handoff key names are pinned in `docs/handoff-contract.md`.

### Seed encoding (do not break)

The seed string in the handoff payload must be url-safe base64 **with `=`
padding** — the app decodes it with `base64Decode` (no normalize), which throws
on un-padded input. `auth.js` has its own padded helper; do **not** reuse
`handoff.js`'s `base64url()` (it strips padding — correct for the fragment, fatal
for the seed). The auth-request JWT segments use JWT-standard base64url *without*
padding.

## Session handoff (landing → WASM app)

Landing and app are different origins, so localStorage is not shared. After auth,
`handoff.js` redirects to the app with the account `{ userId, seed }` in the URL
**fragment** (`{appBase}#th=<base64url(utf8(json))>`); the WASM app captures it
before boot, writes it to its own secure storage, and scrubs it. The fragment
never reaches the server. Field names (`th`, `v`, `userId`, `seed`,
`displayName`) are the contract in `docs/handoff-contract.md`, pinned across both
sides by `scripts/check_handoff_contract.sh` (CI).

`redirectToApp({ userId, seed, displayName? })` is the transport entry point;
`auth.js`'s `signUpWithSeed(...)` produces that payload on a successful signup. To
exercise the transport by hand, serve the landing locally and open
`handoff-dev.html`, paste a known `userId` + `seed`, and click through — the app
should boot already signed in.
