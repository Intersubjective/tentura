# Tentura Invite-Link Onboarding and Auth Plan

> **Status (2026-06-08):** Single-origin routing, session cookies, email magic
> links, Google OAuth, and client/landing invite flows are **shipped**. Phase 3
> (credential Settings polish) and Phase 4 (install-after-click recovery) remain
> partial. This doc is the north-star architecture; shipped routing detail lives
> in [`invite-signup-landing-flow.md`](invite-signup-landing-flow.md); root
> cookie split in [`adr/0002-root-session-routing.md`](adr/0002-root-session-routing.md).
>
> **Key commits:** `50b4fdbf` (single-host Caddy), `a96a5cc4` (root cookie
> routing), `74069ad0` (email magic link), `12157c88` (accept-invite + landing
> hash CTAs), `12bf301c` (signed-out `/` landing), `b575973e` (verified-contact
> account unification).

## Phase summary

| Phase | Goal | Status |
|-------|------|--------|
| **0** | Single-domain routing; static `/invite/*` | **Done** — Caddy prod + local; COOP/COEP scoped to WASM only |
| **1** | Session bootstrap on one origin | **Done** — `__Host-tentura_session`, cookie-presence `/` split, WASM bootstrap, stale-session reconciliation (ADR 0002) |
| **2** | Email magic link (captive-browser auth) | **Done** — server + landing + Resend template; requires `RESEND_*` env |
| **3** | Provider cleanup + credential Settings | **Partial** — list/remove + **link Google/email/recovery seed from Settings** shipped (strict link-mode, per-credential session revoke); retire device-seed landing UI remains |
| **4** | Native + deferred invite pickup | **Partial** — native deep links + Android App Links shipped; install-after-click server tracking not started |

## North Star

Tentura remains invite-only. The main product should feel like a normal social
network:

- `https://tentura.io/` with a valid session opens the product.
- `https://tentura.io/invite/<code>` opens a fast invite page, not Flutter WASM.
- In-app/captive browsers never run Google OAuth, passkeys, or device-key signup
  in place. They get a clear "open in a real browser" path and a recoverable
  email magic-link option.
- Web sessions are `__Host-` HttpOnly cookies owned by the backend. OAuth
  access/refresh tokens and email magic-link state stay server-side. **Exception
  (legacy, still live):** Tier-1 device-seed signup hands the 32-byte seed to
  WASM via `#th=` fragment — see `docs/handoff-contract.md`. Email and Google
  auth set the session cookie only; they do not extend `#th=`.

The app is on one origin in production and dev:

| Environment | Public host |
|-------------|-------------|
| Production | `tentura.io` |
| Dev | `dev.tentura.io` |
| Local | `dev.lvh.me:9443` or equivalent Caddy-backed host |

Single-host routing on the public origin is the only supported topology. There
is no separate app subdomain; invite share links and WASM both use `SERVER_NAME`.

## Why This Shape

Invite links are often opened in Telegram, Instagram, TikTok, WhatsApp, and other
constrained webviews — a bad place for Flutter WASM, Google OAuth, passkeys, or
device keys.

Returning users expect the root domain to be the product when signed in.

The compromise:

- `/invite/*` is the lightweight door.
- `/` is the product when a session cookie is present; otherwise a signed-out
  invite-only landing (`renderNoInvite()`).
- Captive browsers are a degraded surface.
- Email magic links bridge captive browsers to the system browser while
  preserving invite context server-side.

## Route Model

One Caddy site serves these surfaces (strict order matters):

| Route | Surface | Notes |
|-------|---------|-------|
| `/api/auth/*` | Google OAuth start/callback | **Implemented** — Tier 1 only; not `/auth/google/*` |
| `/api/v2/auth/email/start` | Email magic-link start | JSON API |
| `/auth/email/verify` | Email magic-link verify | Sets session cookie, redirects |
| `/api/v2/session/*`, `/api/v2/accounts/*`, `/api/v2/invite/*` | Tentura V2 REST | Proxied to Dart server |
| `/api/*` (catch-all) | Hasura + other API | After Tentura-specific handles |
| `/invite/*` | Static invite shell | No WASM, no COOP/COEP (`handle_path` strips prefix) |
| `/` | **Cookie-presence split** | Cookie → WASM; no cookie → landing index (ADR 0002) |
| `/*` (catch-all) | Flutter WASM app | COOP/COEP scoped here only |

**Not implemented:** `/open` browser-escape helper (Tier-2 escape lives inline in
`main.js` via `webview.js`).

Critical routing invariant:

> `/invite/*` must be handled before the Flutter SPA fallback. It must never
> fall through to `build/web/index.html`.

Reference: `Caddyfile`, `Caddyfile.local`.

## Header Model

Static invite routes must not carry WASM isolation headers:

- no `Cross-Origin-Opener-Policy` on `/invite/*` or signed-out `/`
- no `Cross-Origin-Embedder-Policy` on `/invite/*` or signed-out `/`

WASM routes need:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: credentialless`

Signed-out `/` and cookie-present `/` both emit `Vary: Cookie` and
`Cache-Control: no-store` on the root HTML branch.

## Session Model

```text
__Host-tentura_session=<opaque>; Secure; HttpOnly; SameSite=Lax; Path=/
```

Properties:

- Same origin for landing and WASM.
- Server-only readable; stored in `account_session` (migration `m0081`).
- Used by `/api/v2/invite/:code/preview` (optional-auth), `/api/v2/session/*`,
  and WASM bootstrap (`AuthCase.bootstrapWeb`).
- Short-lived `__Host-tentura_oauth` cookie during Google OAuth (CSRF defense).

**WASM bootstrap order:**

1. Optional `#th=` handoff (device-seed signup only) — consumed once, scrubbed.
2. Session cookie probe → `POST /api/v2/session/access-token` with credentials.
3. Stale cookie: server 401 → logout POST → reload `/` or fallback `/invite/`
   (one-shot `sessionStorage` guard; see ADR 0002).

Email verify and Google callback **set the session cookie** and redirect to
`/invite/<code>?signed_in=1` or `/` — no `#th=` for those flows.

## Account and Credential Model

One account row, many credentials (`account_credential`, migration `m0080`):

| Wire `type` | Enum | Status |
|-------------|------|--------|
| `oidc:google` | `oidcGoogle` | Login + signup on landing (Tier 1) |
| `email_otp` | `emailOtp` | Magic-link login + signup |
| `ed25519_device` | `ed25519Device` | Device-seed signup (landing Tier 1); link via Settings API |
| `webauthn` | `webauthn` | Not started |
| `oidc:apple` | `oidcApple` | Not started |

**Verified contacts** (`account_verified_contact`): authoritative email from
magic-link / Google flows can **link into an existing account** when the contact
matches exactly one account — no silent merge across accounts with conflicting
credentials (`CredentialConflictException` → 409).

Signup vs login (server-side, via `CredentialAuthCase.resolveOrCreate`):

- credential exists → login (+ optional invite accept / beacon forward)
- credential missing + invite present → create account, credential, consume invite
- credential missing + no invite while `isNeedInvite` → refuse (`OidcInviteRequiredException`)
- credential on another account → refuse linking

## Invite Preview

`GET /api/v2/invite/<code>/preview` — same-origin, optional-auth (session cookie
and/or bearer):

```json
{
  "inviter": { "id": "...", "displayName": "...", "image": "..." },
  "codeStatus": "available",
  "callerStatus": "anonymous",
  "beacon": null,
  "suggestedAction": "accept-as-new"
}
```

| `callerStatus` | Landing behavior |
|----------------|------------------|
| `invalid` / `expired` / `consumed` | Explain; no auth CTA |
| `is-inviter` | Open product |
| `already-friends` | Open product |
| `existing-user` | CTA → `{origin}/#/accept-invite/<code>` |
| `anonymous` | Tier-dependent auth UI |

Beacon overlay shown on every valid state. Full client flow:
[`invite-signup-landing-flow.md`](invite-signup-landing-flow.md).

## Browser Tiers

Implemented in `packages/landing/webview.js` + `main.js`.

### Tier 1: System Browser

- Google: `GET /api/auth/google/start?invite=…&returnTo=/invite/…` (when
  `googleEnabled` in landing config)
- Email magic link form
- Device-seed signup (WebCrypto Ed25519; `auth.js` → `#th=` handoff)
- `/invite/<code>` stays static; product opens via same-origin `/` or hash routes

### Tier 2: Captive / In-App Browser

- Primary: open in system browser (`intent://` on Android; copy-link + Safari
  coaching on iOS)
- Secondary: email magic link (always shown)
- **Hidden:** Google OAuth, device-seed signup, passkeys

## Email Magic-Link Flow

**Shipped** (`EmailAuthCase`, `AuthEmailController`, `auth.js`, `main.js`).

### Start

```http
POST /api/v2/auth/email/start
Content-Type: application/json

{
  "email": "user@example.com",
  "inviteCode": "Iabc123"
}
```

Server:

- Normalize + validate format; rate-limit by IP, email, invite.
- On invite-only hosts, **no-invite starts** are skipped unless the address is
  already registered (`email_otp` credential or verified contact) — response
  stays `{ "ok": true }` (enumeration-safe).
- Store single-use row in `email_auth_transaction` (no `return_to` column;
  redirect derived from `invite_code` at verify).
- Send via Resend when `isEmailAuthConfigured`; otherwise start is logged and
  skipped.

Link in email:

```text
https://tentura.io/auth/email/verify?t=<opaque-single-use-token>
```

### Verify

`GET /auth/email/verify?t=...`

1. Atomic consume of token hash.
2. `CredentialAuthCase.resolveOrCreate` with `email_otp` + authoritative email
   contact.
3. Set `__Host-tentura_session`.
4. Redirect: `/invite/<code>?signed_in=1` or `/`.

Landing shows `signed_in` flash and re-previews caller-aware state.

## Google OAuth Flow

**Shipped** (`AuthGoogleController`, `OidcCase`). Tier 1 only (hidden when
`env.inApp`).

```http
GET /api/auth/google/start?invite=<code>&returnTo=/invite/<code>
```

Callback:

```http
GET /api/auth/google/callback?code=…&state=…
```

PKCE + signed `__Host-tentura_oauth` cookie; account resolve via
`OidcCase.completeGoogle`; session cookie set; redirect with `signed_in=1` when
returning to invite page. OAuth tokens never exposed to browser JS.

**Provider console redirect URIs** (not `/auth/google/callback`):

- `https://tentura.io/api/auth/google/callback`
- `https://dev.tentura.io/api/auth/google/callback`
- Local: `https://dev.lvh.me:9443/api/auth/google/callback` (see `Caddyfile.local`)

## Returning User Experience

| URL | Session | Behavior (shipped) |
|-----|---------|-------------------|
| `/` | yes (cookie) | WASM boots authenticated |
| `/` | no | Landing `renderNoInvite()` — invite entry, email/Google behind "I already have an account" |
| `/invite/<code>` | yes | Caller-aware static preview |
| `/invite/<code>` | no, Tier 1 | “I already have an account” → email + Google; separate device-seed signup |
| `/invite/<code>` | no, Tier 2 | “I already have an account” → email + browser escape; card-level browser escape also shown |

## WASM App Responsibilities

| Responsibility | Status |
|----------------|--------|
| Bootstrap from session cookie | **Done** |
| No primary login UI on web | **Done** — unauthenticated web users bounce to landing (`goToLanding`) |
| Accept-invite route + guard + screen | **Done** — see `invite-signup-landing-flow.md` |
| Settings: list credentials | **Done** — `CredentialsScreen` |
| Settings: remove credential (not last) | **Done** — `DELETE /api/v2/accounts/me/credentials/<id>` |
| Settings: link new device key | **Done** — `POST` with `authRequestToken` |
| Settings: link Google / email | **Not done** |
| Revoke sessions on credential remove | **Not done** — JWTs expire ~1h; immediate revoke deferred |
| Retire `#th=` handoff for new auth | **Partial** — email/Google use cookies; device-seed still uses `#th=` |

## Static Invite Responsibilities

`packages/landing` (plain static; no bundler):

| File | Role |
|------|------|
| `index.html` | Shell; Sentry CDN, config, `main.js` |
| `config.js` / `config.local.js` | `apiBase`, `googleEnabled`, `sentryDsn` |
| `main.js` | Preview states, Tier UX, signed-out `/` |
| `invite_entry.js` | Manual invite link/code parsing |
| `preview.js` | `GET /api/v2/invite/:code/preview` |
| `webview.js` | Tier 1/2 detection, Android `intent://` |
| `auth.js` | Email start, device-seed signup |
| `handoff.js` | `#th=` redirect (device-seed only) |
| `app_preload.js` | Background WASM asset warmup from landing |
| `analytics.js` | Sentry funnel events |

## Infra

Single-host deploy is **live** (`50b4fdbf`). Representative Caddy order:

```caddyfile
{$SERVER_NAME} {
  import api

  handle /api/auth/* { reverse_proxy {$TENTURA_UPSTREAM} }
  handle /api/v2/auth/* { reverse_proxy {$TENTURA_UPSTREAM} }
  handle /auth/email/* { reverse_proxy {$TENTURA_UPSTREAM} }
  handle /api/v2/accounts/* { reverse_proxy {$TENTURA_UPSTREAM} }

  handle_path /invite/* {
    root * {$LANDING_ROOT}
    try_files {path} /index.html
    file_server
  }

  # Root cookie-presence split (ADR 0002) — see Caddyfile for @rootWithSession

  handle {
    root * {$APP_ROOT}
    try_files {path} /index.html
    file_server
    header Cross-Origin-Opener-Policy "same-origin"
    header Cross-Origin-Embedder-Policy "credentialless"
  }
}
```

**Remaining topology cleanup (Phase 3):**

- None — single-origin is enforced in code, scripts, and deploy config.

## Phases (detailed)

### Phase 0: Single-Domain Routing and Static Invite Safety — **Done**

Shipped: `Caddyfile`, `Caddyfile.local`, landing static at `/invite/*`, COOP/COEP
on WASM only, same-origin preview.

Acceptance (verify in prod/dev):

- `curl -I /invite/Itest` — no COOP/COEP
- `curl -I /` with/without cookie — correct branch per ADR 0002
- `/invite/Itest` never returns Flutter `index.html`

### Phase 1: Session Bootstrap on One Origin — **Done**

Shipped: session table + cookie, Google OAuth + BFF session, WASM
`bootstrapWeb`, root landing for signed-out `/`, device-seed signup (Tier 1),
`#th=` handoff transport, credentials list/remove API, stale-session
reconciliation.

Acceptance:

- After Google/email login, new tab to `/` enters app authenticated
- Signed-out `/` → landing `renderNoInvite()`
- Stale cookie → one WASM load, cookie cleared, landing (no infinite loop)
- `/invite/<code>` caller-aware when signed in

Refs: `docs/adr/0002-root-session-routing.md`, `docs/handoff-contract.md`.

### Phase 2: Email Magic Link — **Done**

Shipped: `m0082`, `POST /api/v2/auth/email/start`, `GET /auth/email/verify`,
Resend template, landing email form (Tier 1 + 2), invite preserved in
transaction, tests in `email_auth_case_test.dart`.

Acceptance:

- Tier 2: Google hidden, email available
- Magic link sets session, returns to invite with `signed_in=1`
- New account + invite consumes invite; existing account + invite befriends via
  login path (re-preview → `already-friends` or accept-as-existing flow)
- No invite + invite-only: verify refuses new account
- Token reuse / expiry fail; enumeration copy generic

**Ops:** requires `RESEND_API_KEY` + `RESEND_FROM_EMAIL` in server env.

### Phase 3: Provider Cleanup and Credential Settings — **Partial**

| Task | Status |
|------|--------|
| Google Tier 1 only | **Done** |
| List/remove credentials in Settings | **Done** |
| Link device key from Settings | **Done** |
| Link Google / email from Settings | **Not done** |
| Passkey / Apple | **Not done** |
| Retire device-seed from normal landing UI | **Not done** — still Tier-1 new-user path |
| Session revoke on credential remove | **Not done** |
| Topology / single-origin cleanup | **Done** |

Acceptance still open:

- Settings reflects Google and email credentials (list works; add-from-Settings not wired)
- Removing a credential revokes relevant sessions

### Phase 4: Native and Deferred Invite Pickup — **Partial**

| Task | Status |
|------|--------|
| `/invite/*` as public App Link URL | **Done** (Android prod) |
| Native deep-link transform (`invite_deep_link.dart`) | **Done** |
| Accept-invite guard + screen | **Done** |
| Installed app bypasses static landing | **Partial** — Android verified links; iOS/dev → browser → landing |
| Server pending-invite / install-after-click | **Not started** |
| Native OAuth via system browser only | **Existing native auth** — not reworked in this plan |

## Risks and Decisions

1. **Route order is critical.** `/invite/*` before WASM fallback.
2. **Header scoping is critical.** COOP/COEP on invite pages breaks webview flows.
3. **Captive-browser detection is heuristic.** Email always available as fallback.
4. **Email links are bearer credentials.** Short TTL, one-time use, rate limits,
   generic responses.
5. **No account auto-merge.** Verified-contact unification links only on exact
   authoritative match; credential conflicts are explicit 409s.
6. **No OAuth/passkey in webviews.**
7. **Device-seed `#th=` is legacy transport.** New cookie-based flows must not
   put seeds in URLs; device-seed signup remains until Phase 3 retires it.
8. **Static invite remains special.** No WASM on `/invite/*` by design.

## Out of Scope

- Flutter mini-app for invite pages
- OAuth popup as primary auth path
- Google/passkey/device-key signup in captive browsers
- Account merge flow across conflicting credentials
- Flutter deferred imports for invite speed

## Repo Touchpoints

| Area | Paths |
|------|-------|
| Caddy | `Caddyfile`, `Caddyfile.local` |
| Landing | `packages/landing/**` |
| Client routing | `packages/client/lib/app/router/{root_router,accept_invite_guard,invite_deep_link}.dart` |
| Client auth | `packages/client/lib/features/auth/**` |
| Client invite | `packages/client/lib/features/invitation/**` |
| Client credentials | `packages/client/lib/features/credentials/**` |
| Server API | `packages/server/lib/api/{root_router,controllers/auth_*,invite_*,session_controller,account_credentials_controller}.dart` |
| Server domain | `email_auth_case.dart`, `credential_auth_case.dart`, `oidc_case.dart`, `invitation_case.dart`, `session_case.dart` |
| Migrations | `m0080` (credentials), `m0081` (sessions), `m0082` (email transactions) |
| Tests | `packages/client/test/app/{invite_deep_link,accept_invite_guard}_test.dart`, `packages/server/test/domain/use_case/email_auth_case_test.dart` |
