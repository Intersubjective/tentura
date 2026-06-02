# Tentura Invite-Link Onboarding and Auth Plan

> This document replaces the earlier subdomain-split plan. The new target is an
> Instagram-style single public domain: invite links stay fast and static, while
> returning signed-in users opening the root domain land in the full WASM app.

## North Star

Tentura remains invite-only. The main product should feel like a normal social
network:

- `https://tentura.io/` with a valid session opens the product.
- `https://tentura.io/invite/<code>` opens a fast invite page, not Flutter WASM.
- In-app/captive browsers never run Google OAuth, passkeys, or device-key signup
  in place. They get a clear "open in a real browser" path and a recoverable
  email magic-link option.
- Web sessions are `__Host-` HttpOnly cookies owned by the backend. Durable
  credentials, seeds, OAuth tokens, and refresh tokens never travel through URLs
  or JS-readable cross-window payloads.

The app is on one origin in production and dev:

| Environment | Public host |
|-------------|-------------|
| Production | `tentura.io` |
| Dev | `dev.tentura.io` |
| Local | `dev.lvh.me:9443` or equivalent Caddy-backed host |

`app.tentura.io` / `app.dev.tentura.io` become migration artifacts, not the
long-term architecture.

## Why This Shape

The original problem still matters: invite links are often opened in Telegram,
Instagram, TikTok, WhatsApp, and other constrained webviews. Those webviews are a
bad place for large Flutter WASM startup, Google OAuth, passkeys, or device keys.

At the same time, returning users expect a social network home page to be the
product. A user with a valid session opening `tentura.io/` should not see a
marketing/auth page.

The compromise:

- `/invite/*` is the lightweight door.
- `/` and app routes are the product.
- Captive browsers are treated as a degraded surface.
- Email magic links bridge captive browsers to the real browser while preserving
  invite context server-side.

## Route Model

One Caddy site serves three surfaces in strict order:

| Route | Surface | Notes |
|-------|---------|-------|
| `/api/*` | Backend and Hasura proxies | Same origin from browser perspective |
| `/auth/email/*` | Email magic-link start/verify | Backend |
| `/auth/google/*` | Google OAuth start/callback | Backend, Tier 1 only |
| `/invite/*` | Static invite shell | No WASM, no COOP/COEP |
| `/open` | Optional browser-escape helper | Static, no WASM |
| `/*` | Flutter WASM app | COOP/COEP scoped here only |

Critical routing invariant:

> `/invite/*` must be handled before the Flutter SPA fallback. It must never
> fall through to `build/web/index.html`.

`/invite-web/*` is allowed only as a temporary migration alias:

- `/invite-web/<code>` may issue a server-side 302 to `/invite/<code>`.
- New share links should use `/invite/<code>` once route ordering is proven.
- Client-side redirect HTML is discouraged because it adds JS latency in
  webviews.

## Header Model

Static invite routes should not carry WASM isolation headers:

- no `Cross-Origin-Opener-Policy` on `/invite/*`
- no `Cross-Origin-Embedder-Policy` on `/invite/*`
- normal static caching for CSS/JS/images, but no SPA fallback

WASM routes need the existing isolation:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: credentialless`

Because this is one origin, scoping by route is now load-bearing. Do not set
COOP/COEP on the whole vhost unless `/invite/*` is excluded first.

## Session Model

The browser session is:

```text
__Host-tentura_session=<opaque>; Secure; HttpOnly; SameSite=Lax; Path=/
```

Properties:

- Bound to the same origin that serves both invite pages and the WASM app.
- Readable only by the server.
- Used by `/api/v2/invite/:code/preview`, `/api/v2/session/*`, GraphQL/V2
  session bootstrap, and authenticated app APIs.
- OAuth access/refresh tokens, email magic-link state, and provider tokens stay
  server-side.

The WASM app bootstraps from the session cookie. It may keep the old `#th=`
device-seed handoff as a temporary compatibility fallback, but new web auth
flows must not extend it.

## Account and Credential Model

Tentura has one account row and many credentials:

| Type | Use |
|------|-----|
| `oidc_google` | Google login and linking |
| `email_magic` or `email_otp` | Email magic-link login/recovery |
| `ed25519_device` | Optional linked device credential, not primary web transport |
| `webauthn` | Future passkey |
| `oidc_apple` | Future Apple login |

Signup vs login is decided server-side after proving a credential:

- credential exists: login existing account
- credential missing + invite present: create account, store credential, consume
  invite, befriend issuer, forward beacon if present
- credential missing + no invite while invite-only mode is enabled: refuse and
  explain that an invite is required
- credential belongs to another account: refuse linking; do not auto-merge

## Invite Preview

`GET /api/v2/invite/<code>/preview` is same-origin and optional-auth:

- If the session cookie resolves, preview returns the caller-aware state.
- If no session exists, preview returns anonymous state.

Response shape remains:

```json
{
  "inviter": { "id": "...", "displayName": "...", "image": "..." },
  "codeStatus": "available",
  "callerStatus": "anonymous",
  "beacon": null,
  "suggestedAction": "accept-as-new"
}
```

States:

| State | Meaning | Landing behavior |
|-------|---------|------------------|
| `invalid` / `expired` / `consumed` | Code cannot be used | Explain, no auth CTA |
| `is-inviter` | Caller owns the invite | Open product |
| `already-friends` | Caller is already connected | Open product |
| `existing-user` | Caller is signed in but not connected | Open product to accept |
| `anonymous` | No session | Tier-dependent auth UI |

Beacon-forward invite context is shown on every valid state.

## Browser Tiers

### Tier 1: System Browser

Examples: Safari, Chrome, Firefox, desktop browsers.

Allowed actions:

- Open Tentura (`/`) when signed in.
- Continue with Google (`/auth/google/start?invite=...`).
- Email magic link.
- Future passkey and Apple login.

`/invite/<code>` remains static even in Tier 1. It launches auth or opens the
product, but does not itself boot WASM unless the user chooses the product path.

### Tier 2: Captive / In-App Browser

Examples: Instagram, Facebook, Telegram, TikTok, WhatsApp, Twitter/X, Android
System WebView.

Allowed actions:

- Primary CTA: open the same URL in a real browser.
- Android: use an `intent://` browser escape where possible.
- iOS: copy link and coach the user to Safari; do not pretend there is a clean
  programmatic escape.
- Secondary CTA: send an email magic link.

Forbidden in Tier 2:

- Google OAuth
- passkeys/WebAuthn
- device-seed signup
- popups
- writing durable device credentials

Tier detection remains heuristic (`webview.js`), so email magic link should be
available as a safe fallback even when detection misses.

## Email Magic-Link Flow

Email is the primary recoverable path for captive browsers.

### Start

From `/invite/<code>`:

```http
POST /api/v2/auth/email/start
Content-Type: application/json

{
  "email": "user@example.com",
  "inviteCode": "Iabc123",
  "returnTo": "/invite/Iabc123"
}
```

Server responsibilities:

- Normalize email.
- Rate-limit by IP, email, invite, and device fingerprint when available.
- Store a single-use transaction:

```text
email_auth_transaction(
  token_hash,
  normalized_email,
  invite_code,
  return_to,
  created_at,
  expires_at,
  consumed_at,
  user_agent_hash,
  ip_hash
)
```

- Send a generic response regardless of account existence:

```json
{ "ok": true }
```

- Email contains only an opaque one-time token:

```text
https://tentura.io/auth/email/verify?t=<opaque-single-use-token>
```

Do not put email, account id, seed, invite details, OAuth state, or refresh
material in the link.

### Verify

`GET /auth/email/verify?t=...`

Server responsibilities:

1. Hash token and find an unconsumed, unexpired transaction.
2. Mark it consumed atomically.
3. Resolve or create account:
   - existing email credential: login
   - missing email credential + invite present: create account and credential,
     consume invite, befriend issuer, forward beacon
   - missing email credential + no invite in invite-only mode: show invite
     required error
4. Set `__Host-tentura_session`.
5. Redirect:
   - invite present: `/invite/<code>?signed_in=1`
   - no invite: `/`

The redirect back to `/invite/<code>` lets the static page re-preview with the
fresh session and show the right "Open Tentura" or already-connected state.

## Google OAuth Flow

Google remains Tier 1 only.

`GET /auth/google/start?invite=<code>&returnTo=/invite/<code>`

Server responsibilities:

- Generate PKCE verifier, state, nonce.
- Store a single-use OAuth transaction keyed by state with optional invite code
  and return path.
- Set short-lived `__Host-tentura_oauth` cookie for login-CSRF/mix-up defense.
- Redirect to Google.

Callback responsibilities:

- Verify state and oauth cookie.
- Exchange authorization code with PKCE.
- Validate ID token (`iss`, `aud`, `exp`, `nonce`) and read `sub`.
- Resolve/create account exactly like email.
- Set `__Host-tentura_session`.
- Redirect to `/invite/<code>?signed_in=1` or `/`.

No OAuth tokens are exposed to browser JS.

## Returning User Experience

| URL | Session exists | Expected behavior |
|-----|----------------|-------------------|
| `/` | yes | Flutter WASM boots authenticated product |
| `/` | no | Lightweight invite-only explanation with email/Google entry points |
| `/invite/<code>` | yes | Static preview shows caller-aware invite state |
| `/invite/<code>` | no, Tier 1 | Static preview shows Google + email options |
| `/invite/<code>` | no, Tier 2 | Static preview shows browser escape + email |

This is the Instagram-like part: the root domain is the product for signed-in
users. The invite path remains a special fast door because Tentura is
invite-first and webview-heavy.

## WASM App Responsibilities

- Boot from the same-origin session cookie.
- No primary login UI in the app shell.
- If unauthenticated on protected routes, redirect to `/` or a lightweight
  sign-in explanation, not to a subdomain.
- Accept pending invite context after login:
  - via `?invite=<code>` when intentionally passed to the app, or
  - by re-previewing `/invite/<code>` and showing "Open Tentura to accept".
- Settings keeps credential management:
  - list credentials
  - add Google/email/passkey/device credential
  - remove credentials except last credential
  - revoke sessions when a credential is removed where feasible

## Static Invite Responsibilities

Files stay in `packages/landing` unless renamed later:

- `index.html`: static shell
- `main.js`: preview state rendering and CTA wiring
- `preview.js`: same-origin preview fetch
- `webview.js`: Tier 1/Tier 2 detection and browser escape helpers
- `auth.js`: email magic-link start, Google launch, future passkey launch
- `analytics.js`: pre-WASM funnel events
- `styles.css`: lightweight styling

The static shell must stay dependency-light:

- no npm build pipeline
- no bundled React/Vue/etc.
- external scripts minimized
- analytics before WASM

## Infra Migration

Replace subdomain split with one public site.

### Caddy

High-level order:

```caddyfile
{$SERVER_NAME} {
  import api

  handle /auth/email/* {
    reverse_proxy {$TENTURA_UPSTREAM}
  }

  handle /auth/google/* {
    reverse_proxy {$TENTURA_UPSTREAM}
  }

  handle /invite/* {
    root * {$LANDING_ROOT}
    try_files {path} /index.html
    file_server
  }

  handle /open {
    root * {$LANDING_ROOT}
    try_files {path} /index.html
    file_server
  }

  handle {
    root * {$APP_ROOT}
    try_files {path} /index.html
    file_server
    header Cross-Origin-Opener-Policy "same-origin"
    header Cross-Origin-Embedder-Policy "credentialless"
  }
}
```

Exact Caddy syntax should be validated during implementation, but the order and
header scoping are non-negotiable.

### Build and deploy

- Build Flutter web with `SERVER_NAME=https://tentura.io` (or dev host).
- Invite share links use the same host: `/invite/<code>`.
- Landing no longer needs `appBase` for cross-origin app navigation.
- Remove `APP_HOST`, `APP_ORIGIN`, and `INVITE_LINK_HOST` as required public
  topology concepts after migration. Keep temporary compatibility where needed.
- Deploy both `web` and `landing` archives before flipping routing.

### OAuth provider config

Register callbacks:

- `https://tentura.io/auth/google/callback`
- `https://dev.tentura.io/auth/google/callback`
- local HTTPS callback for `dev.lvh.me` if needed

Remove app-subdomain callbacks after traffic is fully migrated.

## Phases

### Phase 0: Single-Domain Routing and Static Invite Safety

Goal: prove one host can serve `/invite/*` statically and `/*` as WASM without
header leakage.

Tasks:

- Add one-host Caddy/dev Caddy routing.
- Make `/invite/*` static before SPA fallback.
- Scope COOP/COEP only to WASM fallback.
- Make landing preview same-origin.
- Keep subdomain routing available behind a temporary compatibility flag only if
  needed for rollback.

Acceptance:

- `curl -I /invite/Itest` has no COOP/COEP.
- `curl -I /` has WASM COOP/COEP.
- `/invite/Itest` never returns Flutter `index.html`.
- Dev HAR for `/invite/*` has no Flutter WASM/bootstrap assets.
- Dev HAR for `/` has normal Flutter app boot.

### Phase 1: Session Bootstrap on One Origin

Goal: root URL behaves like the product for signed-in users.

Tasks:

- Ensure session cookie is set for the single host.
- Simplify preview CORS assumptions to same-origin.
- WASM bootstraps from cookie.
- Landing root probes or links appropriately:
  - signed in: open product
  - signed out: invite-only explanation

Acceptance:

- After Google login, opening a new tab to `/` enters the app authenticated.
- Opening `/invite/<code>` while signed in renders caller-aware static state.
- Opening `/invite/<code>` while signed out renders anonymous state.

### Phase 2: Email Magic Link

Goal: provide recoverable captive-browser auth.

Tasks:

- Add email auth transaction table.
- Add `/api/v2/auth/email/start`.
- Add `/auth/email/verify`.
- Add email template.
- Add landing email form for Tier 1 and Tier 2.
- Preserve invite code server-side through the transaction.

Acceptance:

- In Instagram/Telegram webview, Google is hidden and email is available.
- Magic link opens in system browser, sets session, and returns to invite.
- New account with invite consumes invite and forwards beacon.
- Existing account with invite accepts as existing and forwards beacon.
- No invite + invite-only mode refuses new account.
- Token reuse fails.
- Expired token fails.
- Account enumeration copy is generic.

### Phase 3: Provider Cleanup and Credential Settings

Goal: finish provider model on top of the one-origin session.

Tasks:

- Keep Google Tier 1 only.
- Add email credential listing/removal in Settings.
- Add passkey/Apple later using the same credential model.
- Remove old web device-seed signup from normal UI, or keep it only as a
  clearly labeled legacy path until migrated.
- Remove subdomain `appBase` config and stale redirect assumptions.

Acceptance:

- Credential conflict returns 409.
- Last credential removal is blocked.
- Removing a credential revokes relevant sessions where possible.
- Settings sign-in methods reflects Google and email credentials.

### Phase 4: Native and Deferred Invite Pickup

Goal: native apps preserve invite context without relying on webview auth.

Tasks:

- Universal/App Links keep `/invite/*` as the public link.
- Installed app opens directly and handles invite.
- If install happens after click, server can track pending invite touches.
- Native OAuth uses system browser only.

Acceptance:

- Installed app accepts invite without static landing.
- Not installed opens static invite page.
- Install-after-click can recover pending invite when implemented.

## Risks and Decisions

1. **Route order is critical.** `/invite/*` must not hit Flutter fallback.
2. **Header scoping is critical.** COOP/COEP on invite pages can break webview
   behavior and future popup/link flows.
3. **Captive-browser detection is heuristic.** Always keep email as a fallback.
4. **Email links are bearer credentials.** Short TTL, one-time use, rate limits,
   generic responses, and audit logging are required.
5. **No account auto-merge.** Verified email/provider conflicts must be explicit.
6. **No OAuth/passkey in webviews.** Even if it appears to work in one app, it is
   not reliable enough for the product contract.
7. **No durable credential in URLs.** Invite codes are okay; tokens are opaque and
   single-use; seeds and refresh material are not okay.
8. **Static invite remains special.** Full Instagram parity at `/invite/*` is
   intentionally rejected to keep first invite open fast.

## Out of Scope

- No Flutter mini-app for invite pages.
- No OAuth popup as the primary auth path.
- No Google/passkey in captive browsers.
- No device-key signup in captive browsers.
- No account merge flow.
- No reliance on Flutter deferred imports to make invite pages fast.

## Repo Touchpoints

Representative areas for implementation:

- `Caddyfile`, `Caddyfile.local`, `compose.prod.yaml`
- `.github/workflows/pipeline.yml`
- `scripts/resolve_*_web_config.sh`
- `packages/landing/**`
- `packages/client/lib/consts.dart`
- `packages/client/lib/env.dart`
- `packages/client/lib/app/router/root_router.dart`
- `packages/client/lib/features/auth/**`
- `packages/client/lib/features/settings/**`
- `packages/server/lib/api/root_router.dart`
- `packages/server/lib/api/controllers/*`
- `packages/server/lib/api/middleware/auth_middleware.dart`
- `packages/server/lib/domain/use_case/oidc_case.dart`
- `packages/server/lib/domain/use_case/invitation_case.dart`
- Drift migrations for email auth transactions and credential metadata
