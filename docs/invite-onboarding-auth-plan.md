# Tentura Invite-Link Onboarding & Multi-Credential Auth — Phased Execution Plan

> **How to use this document.** It is a program-level plan split into self-contained
> phases (0→3). Execute one phase per plan-mode session: open this file, read the target
> phase, run that phase's own plan-mode pass to produce line-level steps, build, verify
> against the phase's Acceptance Criteria, then move to the next phase. Phases are ordered
> by dependency; later phases assume earlier ones shipped.

> **⚠️ ARCHITECTURE REVISION — read before any auth work.** After the server-foundation
> slice we changed two things: (1) the web→app **session transport** and (2) the **role of
> Ed25519**. The seed-in-URL handoff (`#th=<seed>`) and the "device key is the cross-surface
> identity" assumption are **superseded** for all remaining auth work by an **OAuth/OIDC +
> session-cookie (BFF)** model — see the canonical **§ Architecture revision** below (after
> Target Architecture). Slices already shipped on the old model still run, but **do not
> extend them**: build new providers (Google/Apple/passkey/email) and the WASM login removal
> on the revised model (the WASM login *removal* already shipped; its session now moves from
> the `#th=` handoff to the `__Host-` cookie). Ed25519 is now **one optional
> `account_credential`**, not the bridge.

---

## Context

Tentura is invite-link-only and stays that way. Every new user arrives via an invite URL,
frequently opened inside in-app webviews (Telegram, Instagram, TikTok, WhatsApp). Today
the product is a single Flutter **web WASM** app served at the root domain: the clicker
waits for bundle download + WASM compile + DI bootstrap (`AuthCubit` preResolve, Hive,
Drift, Ferry, Sentry, FCM) + first frame + AutoRoute guards before any registration/intro
UI appears — 3–6s+ in memory-constrained webviews, where Google OAuth and passkeys are
also blocked.

**Goal:** move all invite + web-auth flows to a fast static landing at **`tentura.io`**,
keep the WASM app (no login UI) at **`app.tentura.io`**, and replace the
"device Ed25519 keypair *is* the account" model with a server-side multi-credential
account model so users can add/recover passkey, Google, Apple, and email alongside the
device key. **The device key is just one `account_credential`, not the cross-surface
identity transport: web sessions ride an `__Host-` HttpOnly cookie issued by the app-host
backend acting as a confidential OAuth client (BFF) — see § Architecture revision.**

**Domains.** Production: `tentura.io` (landing) + `app.tentura.io` (WASM app).
**`dev.tentura.io`** is the **only live deploy today** (no prod users yet) and uses the
**same subdomain split** as prod: `dev.tentura.io` (landing) + `app.dev.tentura.io`
(WASM app). See Phase 0 § Infra and § `SERVER_NAME` split.

---

## Current State (grounded in the repo)

**Auth model — the Ed25519 public key literally is the account.**
- `packages/server/lib/domain/use_case/auth_case.dart`: client signs an EdDSA
  "auth request" JWT; server verifies it against the public key in the payload
  (`_verifyAuthRequest`), looks up the user by public key (`getByPublicKey`), and mints a
  server-signed session JWT (`_issueJwt`, server Ed25519 key).
- `signUp` branches on `env.isNeedInvite`: when set it requires an invite code in the
  payload and calls `_userRepository.createInvited(...)`; else `create`.
- Identity column: `users.public_key` (Drift-managed).

**Invite system — dual semantics AND beacon-forward already exist.**
- `packages/server/lib/domain/use_case/invitation_case.dart`:
  - `create({userId, beaconId})` — issuer mints an invite; **optional `beaconId`**.
  - `fetchById` — rejects accepted/expired.
  - `accept` → `_userRepository.bindMutual(invitationId, userId)` — befriend path for an
    already-authenticated user → maps to proposal's **`accept-as-existing`**.
  - `createInvited` (from `signUp`) — signup + friendship → maps to **`accept-as-new`**.
- **Beacon-forward invite is fully implemented.** `InvitationEntity` carries `beaconId`
  (`packages/server/lib/domain/entity/invitation_entity.dart`), and **both** code paths
  already insert a beacon forward when `beaconId != null`:
  - `createInvited` — `packages/server/lib/data/repository/user_repository.dart:99`
    (`forwardCount: 1`).
  - `bindMutual` — `user_repository.dart:204` (`forwardCount: 1`).
  - These invites are created from the beacon forward screen
    (`packages/client/lib/features/forward/ui/screen/forward_beacon_screen.dart:205`
    `_inviteNewPerson` → `InvitationCubit.createInvitation(beaconId: …)`).
  - **Consequence:** `accept-as-new` / `accept-as-existing` inherit beacon-forwarding for
    free by wrapping those methods. The only NEW work is *surfacing* the beacon in the
    preview response and landing UI.

**Invite link format.** `{INVITE_LINK_HOST}/invite/<invitationId>` via `inviteShareUri()` in
`packages/client/lib/consts.dart` (forward + friends screens). The invitation id is the
"code" (prefix `'I'`). Legacy `/shared/view?id=I…` URLs are not supported.

**Schema is owned by Drift, not Hasura.**
- `packages/server/lib/data/database/migration/m0001…m0072.dart`; snapshots in
  `packages/server/drift_schemas/`. Hasura (`hasura/metadata.json`) is GraphQL-on-top.
- Multi-credential = new migration **m0073+** plus Hasura metadata regen.

**OG/preview SSR already exists (Jaspr).**
- `packages/server/lib/api/controllers/shared_view_controller.dart` renders OG-tagged HTML
  via Jaspr `renderComponent` for beacons/users/**invitations** (`'I' =>
  _invitationCase.fetchById`), using
  `packages/server/lib/api/view/shared_view/components/invitation_view_component.dart`.
- It already does the **crawler-vs-browser split**: with `renderSharedPreview` off and a
  `Mozilla` UA it 302-redirects to the SPA (path in URL fragment); else renders preview
  HTML. Precursor to the proposal's preview endpoint.

**Routing (Phase 0 — subdomain split, implemented).** [`Caddyfile`](../Caddyfile):
- Shared `(api)` snippet on **both** hosts: `/api/v1/graphql` → Hasura;
  `/api/v2/graphql`, `/api/v2/ws`, `/api/v2/room-attachments/*`, `/shared/*`,
  `firebase-messaging-sw.js` → Dart server (`tentura:2080`); `handle_path /api/*` → Hasura.
- **`{$SERVER_NAME}`** (landing): `{$LANDING_ROOT:/srv/landing}` static files; **no**
  COOP/COEP; `handle_errors` 404 → maintenance text; pgAdmin only here.
- **`{$APP_HOST}`** (WASM app): `{$APP_ROOT:/srv/web}` at root (`--base-href=/`); COOP
  `same-origin` + COEP `credentialless` **only on this host** (Risk #1).
- **Local:** [`Caddyfile.local`](../Caddyfile.local) — `http://dev.lvh.me:9080` +
  `http://app.dev.lvh.me:9080` (or `.test` hosts via `/etc/hosts`); see
  [`compose.dev.yaml`](../compose.dev.yaml) header.
- **Historical:** pre–Phase 0, a single host served the SPA at `/` with COOP/COEP on
  everything; path-based `/app/*` on dev was considered then **superseded** by subdomain-on-dev.

**Optional auth middleware exists.** `packages/server/lib/api/middleware/auth_middleware.dart`:
`extractJwtClaims` (non-failing; on the GraphQL endpoint) vs `verifyBearerJwt` (failing).
The preview endpoint needs the **non-failing** variant.

**Client auth/invite surface.** `packages/client/lib/features/auth/` (`auth_cubit.dart`
@singleton/preResolve, `auth_local_repository.dart` seed storage, `auth_login_screen.dart`,
`auth_register_screen.dart`); `packages/client/lib/features/invitation/`.

---

## Target Architecture (high level)

- **`tentura.io`** — new static landing (**`packages/landing`**, monorepo). All
  invite + web-auth flows. 300–800ms TTI; works in webviews; OG previews; OAuth redirect
  URIs; native WebAuthn in DOM; in-app-browser detection. **Deps-light: no npm, no build
  toolchain** — plain static HTML/CSS/JS served as-is. Pull in a JS library only when truly
  needed, loaded **in-browser** (CDN ESM `import`, or a single vendored file checked into the
  repo) — never via a Node/npm build. Keep external scripts to the minimum (see analytics).
- **`app.tentura.io`** — existing Flutter WASM app + **auth backend (BFF / session owner)**,
  **no login UI**; unauthenticated → redirect to landing; receives its session as an
  `__Host-` HttpOnly cookie from the backend (the seed-in-URL handoff is **superseded** — see
  § Architecture revision); keeps `Settings > Sign-in methods`.
- **Native iOS/Android (and future Linux/Windows/macOS)** — **system-browser** OAuth/OIDC
  with Authorization Code + PKCE (RFC 8252), **never embedded webviews**; Universal Links /
  App Links for invites (installed → app, else → landing); refresh/session in
  Keychain/Keystore/Secret Service/Credential Manager. Same preview endpoint, same UI states.
- **Server** — one `accounts` row, many `account_credentials` rows
  (`ed25519_device`, `webauthn`, `oidc:google`, `oidc:apple`, `email_otp`). Invite
  consumption at account creation only; **signup-vs-login is decided at the OAuth callback by
  a `(provider, sub)` lookup** (see § Architecture revision).
- **Preview endpoint** decides what an invite means for *this* clicker before any UI,
  including the **beacon-forward** variant.

**Phase dependency graph**
```
Phase 0  landing + preview endpoint + OG + analytics   ── ships on TODAY's auth
   │  (independent of Phase 1)
   ▼
Phase 1  multi-credential server + migration + landing signup
   ▼
Phase 2  intro tour on static HTML before WASM handoff
   ▼
Phase 3  (optional) deferred deep link / pending-invite pickup (native)
```

---

## Architecture revision: session-cookie (BFF) + OAuth/OIDC model

> **Status: canonical for all remaining auth work.** Supersedes the seed-in-URL handoff
> (recap slice 1) and the "Ed25519 device key is the cross-surface identity" assumption for
> **slice 4+ and every deferred provider**. The shipped device-seed signup (slice 3) and
> `#th=` fragment handoff still run and may remain as a *fallback*, but **new providers
> (Google/Apple/passkey/email) and the WASM session rework MUST follow this model, not extend
> the seed handoff** (the WASM login *removal* itself already shipped in slice 4). Grounded in
> [RFC 9700](https://www.rfc-editor.org/info/rfc9700/) (OAuth
> 2.0 Security BCP), [RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252) (OAuth for
> Native Apps), and the IETF *OAuth 2.0 for Browser-Based Apps* BCP draft (BFF pattern).

### Why the change (two defects in the seed-handoff model)

1. **Seed in a URL fragment is an exposed long-lived credential.** `{appBase}#th=<seed>`
   keeps the secret out of the HTTP *request* (fragments aren't sent to servers), but it is
   still readable by page JS, browser extensions, `history`/session-restore, screenshots, and
   malware. Shipping the durable account seed there negates the app's encrypted
   `LocalSecureStorage` — the secret already crossed an unsafe channel before storage.
2. **Ed25519 was never meant to be the primary identity bridge.** The goal is Ed25519 as
   *one* credential among many (`account_credential`), not the mandatory transport tying
   landing ↔ web ↔ native together. Forcing every provider to mint and ship a device seed is
   backwards.

### The rule (pin this)

> **Cross-origin navigation may carry only opaque, short-lived, single-use transaction
> identifiers. Durable credentials, account seeds, refresh tokens, and OAuth tokens never
> travel through URLs or JS-readable cross-domain payloads.**

### The one fact everything depends on (same-site, cross-origin)

`tentura.io` (landing) and `app.tentura.io` (app + auth backend) are **different origins but
the same _site_** (shared registrable domain `tentura.io`). Therefore:

- **cross-origin** → no shared `localStorage`; the app's `__Host-` session cookie is not
  readable by landing JS;
- **same-site** → `SameSite=Lax` cookies *are* sent on requests between them, and Safari ITP
  / third-party-cookie blocking does **not** apply.

**Do not move the app to a separate registrable domain** (e.g. `tenturaapp.com`) — that makes
the two cross-*site*, forcing `SameSite=None` and reintroducing third-party-cookie problems.
The subdomain split is load-bearing.

### Session model (web = BFF / token-mediating backend)

- The **app-host backend is a confidential OAuth client** and the **session owner**.
- Browser holds only `__Host-tentura_session` — **Secure, HttpOnly, SameSite=Lax, Path=/, no
  Domain** (`__Host-` ⇒ bound to `app.tentura.io` exactly). OAuth access/refresh tokens stay
  server-side; JS never sees them; nothing durable in `localStorage`.
- If pure-cookie API auth is hard with the Hasura/V2 split, use a **token-mediating backend**:
  HttpOnly session cookie + `GET /api/session/access-token` returning short-lived access
  tokens held **in memory only**.

### Auth-state detection from the landing (`credentials: 'include'`)

The landing learns who the clicker is via a **same-site credentialed fetch to the app host**
(not via the landing-host `/api` proxy):

```js
fetch('https://app.tentura.io/api/v2/invite/:code/preview', { credentials: 'include' })
```

`credentials: 'include'` is a *mode*, **not** an assertion that a credential exists: the
browser attaches the `app.tentura.io` session cookie **iff one exists**, else sends none.

- logged-in → cookie rides along (same-site) → server returns `existing-user` /
  `already-friends` / `is-inviter`;
- logged-out / new → no cookie → server returns `anonymous`.

CORS on the app host must return `Access-Control-Allow-Origin: https://tentura.io` +
`Access-Control-Allow-Credentials: true` (origin cannot be `*` with credentials). COOP/COEP on
the app host do **not** block *receiving* a credentialed fetch — they only constrain what the
app host embeds/popups. HttpOnly is preserved: the landing reads only the JSON, never the
cookie value.

### Auth launch (top-level redirect, not popup)

Provider CTAs are **top-level navigations** to app-host backend endpoints — **not popups**:

- `GET /api/auth/{provider}/start?invite=I…` — generate PKCE verifier + `state` + `nonce`;
  persist a server-side auth-transaction `{inviteId, returnTo, createdAt}` **keyed by
  `state`**; set a short-lived `__Host-tentura_oauth` cookie binding `state` to the UA
  (login-CSRF / mix-up defense); 302 to the provider.
- `GET /api/auth/{provider}/callback` — verify `state` vs cookie, exchange `code` + verifier
  (Authorization Code + PKCE — **never implicit, never tokens in URL**), validate the ID token
  (`iss`/`aud`/`exp`/`nonce`), read `sub`.

Because launch is a top-level redirect, **COOP `same-origin` is irrelevant to it** — this
removes Risk #1 for the boot/login path (it survives only for an optional Settings-linking
popup, if one is ever used).

**Invite code travels in the server-side `state`-keyed record, NEVER in `redirect_uri`**
(RFC 9700 requires exact pre-registered redirect URIs → one fixed callback per provider).

### Signup-vs-login is decided at the callback, not on the landing

At `/callback`, look up `(provider, sub)` in `account_credential`:

- **not found → new account** → run **`accept-as-new`** (create account + store credential +
  consume invite + befriend issuer + forward beacon, atomically);
- **found → existing account** → run **`accept-as-existing`** (befriend + forward beacon; no
  account creation, no signup-slot consumption).

This is why **one** "Continue with Google" button serves both signup and login, and why a
**logged-out existing user is indistinguishable from a new user at preview time** — the server
disambiguates *after* auth.

### Invite flow — the three cases (web + native)

| Case | Web | Native (mobile) |
|---|---|---|
| **1. New user (signup)** | landing preview = `anonymous` → provider CTAs → `/auth/start` → callback: `(sub)` not found → `accept-as-new` → set session cookie → 302 to app | not installed → landing in browser (web flow). installed → App/Universal Link opens app → app launches **system-browser** OAuth (`ASWebAuthenticationSession`/Custom Tab, never embedded webview) + invite → backend `accept-as-new` → session to app |
| **2. Existing, authenticated** | landing preview (credentialed) = `existing-user` / `already-friends` / `is-inviter` → open app; befriend runs via authenticated `accept-as-existing` (app-on-boot or app-host call) | Universal/App Link **bypasses landing**, opens app directly → app has session → `accept-as-existing` (befriend + beacon) |
| **3. Existing, logged out** | preview = `anonymous` (same as case 1) → **same provider CTAs** → callback: `(sub)` **found** → login → `accept-as-existing` (not `accept-as-new`) → session cookie | installed + logged-out → App Link opens app → no session → system-browser OAuth → backend login → `accept-as-existing`. not installed → web flow |

**Hard variant (OUT OF SCOPE — needs account merge):** a logged-out existing user signs up
with a *different* method than they joined with → a second account is created. Merge is
deliberately out of scope. **Cheap mitigations to add now so fewer orphans accrue:** (a) at
callback, if the new credential's *verified email* already belongs to another account, **refuse
to create** and redirect to "you already have an account — continue with <original provider>";
(b) a UX nudge "use the method you joined with". Both require storing/normalizing a verified
email per account.

### Ed25519 demoted to an optional device credential

Ed25519 is linked **after** an authenticated session exists, **generated in the app origin**
(so app-origin secure storage stays meaningful), via the existing
`POST /api/v2/accounts/me/credentials`. It is **never** the cross-domain transport. For
user-facing public-key auth on web, **prefer WebAuthn/passkeys** over custom Ed25519 (origin
binding, phishing resistance, platform sync/recovery, non-exportable keys).

### Native / desktop (future Android, iOS, Linux, Windows, macOS)

- **Authorization Code + PKCE in the system browser** (`ASWebAuthenticationSession` iOS,
  Custom Tabs + App Links Android, system browser + loopback `127.0.0.1:{random_port}` on
  desktop). **Never embedded webviews** for OAuth (RFC 8252).
- Invite deep links via **Universal Links (iOS) / App Links (Android)** on
  `tentura.io/invite/*`: installed → app (skip landing); not installed → landing in browser.
- Refresh/session material in **Keychain / Android Keystore / Secret Service (libsecret) /
  Windows Credential Manager** — not plaintext, never in URLs.
- Invite always travels as **server-side auth state keyed by `state`**, never as a
  secret-bearing client payload. Phase 3 (deferred deep-link pickup) covers
  install-after-click.
- Normalize every provider server-side into the same `account_credential` table.

---

# PHASE 0 — Static landing + preview endpoint + OG + analytics

**Goal.** Ship `packages/landing` at `tentura.io` and a JSON preview endpoint, running on
**today's single-credential auth**. No multi-credential work. Auth CTAs may be
feature-flagged/stubbed (wired in Phase 1); the **beacon-forward** and **befriend** flows
that already work server-side should be exercised end-to-end.

**Prerequisites.** None (independent of Phase 1).

### Implementation status (repo)

| Area | Status | Notes |
|------|--------|--------|
| JSON preview endpoint | **Done** | Case tests + `dart analyze`; live curl matrix **owed** |
| `packages/landing` static shell | **Done** | 5 states + beacon overlay; `AUTH_ENABLED=false` |
| `docs/handoff-contract.md` | **Done** | Keys pinned; CI pin **not yet** wired |
| Caddy subdomain split | **Done** | `Caddyfile`, `compose.prod.yaml`, `deploy.sh`, `pipeline.yml` |
| `Caddyfile.local` | **Done** | `dev.lvh.me` / `app.dev.lvh.me`; `caddy validate` + curl checks |
| Deploy to `dev.tentura.io` | **Pending** | Needs DNS for `app.dev.tentura.io` + env vars below |

### Locked decisions (Phase 0 — do not relitigate)

- **`preview()`** uses `getById` (nullable), **not** `fetchById` (throws on consumed/expired).
- **`codeStatus`:** `available` \| `consumed` \| `expired` \| `invalid` — **no `revoked`**
  in Phase 0 (not modeled; deleted row → `invalid`).
- **already-friends:** reuse `VoteUserFriendshipLookup.isReciprocalSubscribe` — **no**
  new `areFriends` on `UserRepositoryPort`.
- **Landing:** plain static HTML/JS; **no npm/bundler**; Sentry CDN = only external script.
- **Routing:** **subdomain on dev** (mirrors prod), **not** path-based `/app/` on
  `dev.tentura.io`. WASM build: `--base-href=/`.

### Server — preview endpoint (JSON, REST on `root_router`)
- Add `GET /api/v2/invite/:code/preview` to
  `packages/server/lib/api/root_router.dart`, guarded by `_authMiddleware.extractJwtClaims`
  (non-failing) so anonymous vs existing-user is distinguishable.
- New controller `packages/server/lib/api/controllers/invite_preview_controller.dart`
  returning:
  ```
  { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }
  ```
  - `codeStatus`: `available` \| `consumed` \| `expired` \| `invalid` (Phase 0; no
    `revoked` — see locked decisions).
  - `callerStatus`: `anonymous` \| `existing-user` \| `already-friends` \| `is-inviter`
    (self-invite blocked).
  - `beacon`: present iff `invitation.beaconId != null` — title/snippet via
    `BeaconRepositoryPort`.
- **`InvitationCase.preview(...)`** (implemented): `getById` for code status;
  `VoteUserFriendshipLookup.isReciprocalSubscribe` for already-friends;
  `InvitePreviewResult` in `packages/server/lib/domain/entity/invite_preview_result.dart`;
  `InvitePreviewController` → `GET /api/v2/invite/<code>/preview` with
  `extractJwtClaims` (non-failing).
- **OG meta stays on the existing Jaspr path** (`shared_view_controller` +
  `invitation_view_component`) for Telegram/iMessage crawlers; keep its output consistent
  with the JSON preview (crawler path only; user-facing shares use `/invite/:code`).

### Landing — `packages/landing` (static package, implemented)
- Plain static HTML/CSS/JS, served **as-is** — **no build step, no npm, no `node_modules`,
  no bundler**. Caddy serves `{$LANDING_ROOT}` directly. JS libraries only as needed,
  loaded in-browser (CDN ESM or a vendored single file).
- **Runtime config** (`config.js`): `apiBase: ''` (landing host proxies `/api`);
  `appBase` absolute app origin (CI injects `APP_BASE`, default
  `https://app.dev.tentura.io/`). Invite URLs: `/invite/:code` (`I…` id) on the landing host.
- In-app-webview detection → two-tier UX:
  - **Tier 1 (system browser):** full auth CTAs (Passkey/Google/Apple/Email) —
    **feature-flagged off / stubbed in Phase 0**, wired in Phase 1.
  - **Tier 2 (in-app webview):** primary "Open in your browser" (Android `intent://`;
    iOS copy-link + coach to Safari — **no clean programmatic iOS escape; the explicit tap
    is the design, per the proposal — do not engineer an escape**); secondary degraded
    email/Ed25519 path (lands in Phase 1).
- Render the five preview states: invalid / is-inviter / already-friends /
  existing-user (befriend) / anonymous (three ordered CTAs: open app via Universal Link →
  "I already have an account, open in browser" → "I'm new, sign up").
- **Beacon-forward overlay:** when `beacon` is present, every state shows the shared
  beacon context above the CTA ("Alice shared **<beacon>** and wants to connect").
- Funnel analytics firing **before** any WASM — a first-class Phase 0 deliverable. Use the
  **Sentry browser SDK loaded from its CDN** (the single allowed external `<script>`); no npm.

### Infra — routing for prod AND dev (implemented)

**Topology**

| Host | Serves | Caddy env |
|------|--------|-----------|
| `dev.tentura.io` | Static landing | `SERVER_NAME`, `LANDING_ROOT=/srv/landing` |
| `app.dev.tentura.io` | WASM + same `(api)` routes | `APP_HOST`, `APP_ROOT=/srv/web` |
| `tentura.io` / `app.tentura.io` | Same pattern when prod exists | same vars, prod values |

**`SERVER_NAME` split (client vs server)**

The Flutter client compiles one `kServerName` used for **API/WS** and **share links**
(`packages/client/lib/consts.dart`). Phase 0 intentionally splits build-time vs runtime:

| Variable | Required | Where | Phase 0 dev value | Purpose |
|----------|----------|-------|-------------------|---------|
| `CLIENT_SERVER_NAME` | **Yes** | GitHub `dev` → [`resolve_deploy_web_config.sh`](../scripts/resolve_deploy_web_config.sh) → `--dart-define=SERVER_NAME` | `https://app.dev.tentura.io` | GraphQL/WS same-origin on app host |
| `IMAGE_SERVER` | **Yes** | GitHub `dev` → resolver → `--dart-define=IMAGE_SERVER` | CDN base URL | Image URLs in client |
| `INVITE_LINK_HOST` | No (derived) | Resolver → `--dart-define=INVITE_LINK_HOST` | `https://dev.tentura.io` | Invite share links `/invite/I…` |
| `APP_BASE` | No (derived) | Resolver → CI `sed` on `config.js` | `https://app.dev.tentura.io/` | Landing CTAs → WASM (`appBase`) |
| `SERVER_NAME` | VPS only | `.env` → Tentura container | `https://dev.tentura.io` | OG tags, Jaspr `/shared/view`, server `kServerName` |
| `APP_HOST` | VPS only | `.env` → Caddy | `app.dev.tentura.io` | Second TLS site block |

Share links from the app use `INVITE_LINK_HOST` (`/invite/I…` on the landing host). OG
crawlers still hit Jaspr `/shared/view?id=…` on whichever host proxies `/shared/*`.

**CICD / deploy**

- [`pipeline.yml`](../.github/workflows/pipeline.yml): `resolve_deploy_web_config.sh` (fail-fast);
  `flutter build web --base-href=/`; landing tar + resolved `APP_BASE` / `LANDING_SENTRY_DSN`.
- [`deploy.sh`](../deploy.sh): extract web + landing **before** `compose up`; placeholder
  `index.html` if `LANDING_DIR` empty.
- [`compose.prod.yaml`](../compose.prod.yaml): mounts `./web`, `./landing`; proxy env
  `APP_HOST`, `APP_ROOT`, `LANDING_ROOT`.

**Deploy prerequisites (ops)**

1. DNS: `app.dev.tentura.io` → VPS (or `*.dev.tentura.io` wildcard).
2. VPS `.env`: `SERVER_NAME=https://dev.tentura.io`, `APP_HOST=app.dev.tentura.io`,
   `APP_ROOT=/srv/web`, `LANDING_ROOT=/srv/landing`, `ACME_EMAIL=…`.
3. GitHub **dev** variables: **required** `CLIENT_SERVER_NAME`, `IMAGE_SERVER`; optional
   `INVITE_LINK_HOST`, `APP_BASE` (auto-derived when unset). See `CI_CD_SETUP.md`.

**Local simulation** — [`Caddyfile.local`](../Caddyfile.local):

- `http://dev.lvh.me:9080` (landing), `http://app.dev.lvh.me:9080` (app); `auto_https off`.
- Default: app host → `flutter run` on `:8888`; `LOCAL_USE_FLUTTER_PROXY=off` → static
  `packages/client/build/web`.
- Landing `config.js` for local: `appBase: 'http://app.dev.lvh.me:9080/'`, `apiBase: ''`.
- Offline: `/etc/hosts` → `dev.tentura.test`, `app.dev.tentura.test` + Caddy env overrides.

**Deploy ordering (Risk #1):** ship landing + web archives **before** switching Caddy to
subdomain split, or rely on `deploy.sh` placeholder + `handle_errors` so apex never 404s
empty.

### Handoff contract (define now; exercised in Phase 1)

> **⚠️ SUPERSEDED as the path forward.** The `#th=<seed>` fragment handoff below shipped and
> still runs, but it carries a durable seed through a JS-readable channel and is **replaced**
> for slice 4+ by the `__Host-` cookie session from the app-host backend — see
> **§ Architecture revision**. Keep this section for historical/fallback context only; do not
> build new providers on it.

Authoritative payload + cross-subdomain notes: [`docs/handoff-contract.md`](handoff-contract.md).

- Dev/prod are **cross-subdomain** (`dev.tentura.io` ↔ `app.dev.tentura.io`).
- **Implemented (Phase 1 slice 1):** transport is a **one-time URL-fragment redirect**
  (`{appBase}#th=<base64url(json)>`), **not** a cookie/postMessage. The original
  "landing writes the app's localStorage keys" model was dropped — it's both cross-origin
  *and* the app's secure storage is encrypted/key-prefixed; the app itself does the write.
- CI pin for key strings: **wired** (`scripts/check_handoff_contract.sh` in `pipeline.yml`).

### Files (Phase 0 — in repo)

**Server:** `packages/server/lib/api/controllers/invite_preview_controller.dart`,
`packages/server/lib/domain/entity/invite_preview_result.dart`,
`packages/server/lib/domain/use_case/invitation_case.dart`,
`packages/server/lib/api/root_router.dart`,
`packages/server/test/domain/use_case/invitation_case_test.dart` (+ mocks).

**Landing:** `packages/landing/**` (`index.html`, `config.js`, `main.js`, `preview.js`,
`webview.js`, `analytics.js`, `styles.css`, `README.md`).

**Infra:** `Caddyfile`, `Caddyfile.local`, `compose.prod.yaml`, `deploy.sh`,
`.github/workflows/pipeline.yml`, `.github/actions/deploy-web-archive/action.yml`.

**Docs:** `docs/handoff-contract.md`, this file.

### Acceptance criteria

| Criterion | Status |
|-----------|--------|
| `curl GET /api/v2/invite/:code/preview` — all `codeStatus`/`callerStatus` + beacon | **Unit tests done**; live curl on dev stack **owed** |
| OG crawler `/shared/view?id=I…` (not user share URLs) | **Verify on deploy** |
| Landing: 5 states + beacon; Sentry before WASM | **Implemented**; TTI/funnel on deploy **owed** |
| Caddy: landing no COOP; app COOP/COEP; both proxy `/api` | **`caddy validate` + local curl done**; live dev hosts **owed** |

**curl matrix (when dev stack is up):** anonymous / issuer JWT / friend / stranger /
consumed / expired / invalid id / invite with `beaconId` — see Phase 0 line-level plan or
handoff session notes.

---

# PHASE 1 — Multi-credential server model + migration + landing signup

**Goal.** Replace "public key is the account" with one account + many credentials; wire
real auth on the landing; remove web login UI from the WASM app; split invite acceptance
into explicit endpoints (preserving beacon-forward).

**Prerequisites.** Phase 0 (preview endpoint, landing shell, handoff contract).

### Implementation status (repo)

Detailed shipped-status + gotchas live in
[`phase-1-server-foundation-recap.md`](phase-1-server-foundation-recap.md); this is the
program-level summary.

| Area | Status | Notes |
|------|--------|--------|
| Migration + `account_credential` table | **Done** | Landed as `m0080` (not m0073 — repo had reached m0079). `users.public_key` kept & dual-written; no Hasura ripple, no snapshot to regen. |
| `signIn` resolves via credential | **Done** | `getByCredential('ed25519_device', pk)`. |
| Split invite accept endpoints | **Done** | `accept-as-new` / `accept-as-existing` (REST, additive; GraphQL stays). |
| Session handoff (slice 1) | **Done** | URL-fragment redirect; CI-pinned. Live cross-subdomain E2E **owed**. |
| `/accounts/me/credentials` link/list/remove (slice 2) | **Done (infra + `ed25519_device`)** | Conflict→409, last-credential→409. **Deferred:** WebAuthn/OIDC/email-OTP providers; immediate session revocation (1h JWT expiry is interim). |
| Landing real auth | **Done (device-seed, Tier-1 only)** | Slice 3. `auth.js`: WebCrypto-Ed25519 signup → `accept-as-new` → handoff. **Deferred:** passkey/Google/Apple/email providers; **Tier-2 in-app webviews never get device-seed signup** (unrecoverable key loss) — email path is their future method. Live E2E owed on HTTPS dev stack. |
| Client WASM (remove login UI, Settings sign-in methods) | **Pending** | Slice 4 — where the COOP/popup constraint (Risk #1) gets validated. |
| OAuth/OIDC + BFF session (Architecture revision) | **Done (code)** | `account_session` (m0081), `/api/v2/session/*`, Google `/api/auth/google/*`, preview credentialed CORS, landing Google CTA + appBase preview, client cookie bootstrap. **Deferred:** live Google OAuth on HTTPS dev stack; session revoke on credential removal. |

### Server — Drift migration m0073+
- New table `account_credentials(account_id, type, identifier, public_data, created_at, …)`,
  unique index on `(type, identifier)` (OIDC `sub`, WebAuthn credential id, device public
  key). Add migration under `packages/server/lib/data/database/migration/m0073*.dart`.
- Keep `users` as the account row (avoid a physical rename that ripples through Hasura/
  GraphQL — decide in the phase's detailed plan).
- **Data step (idempotent, reversible):** backfill one `ed25519_device` credential per
  existing user from `users.public_key`. Regenerate `drift_schemas/` snapshot and
  **`hasura/metadata.json`**; regenerate Ferry `_g` GraphQL codegen if shapes change.

### Server — auth + credential endpoints (revised model — see § Architecture revision)
- **OAuth/OIDC backend on the app host (BFF):** `GET /api/auth/{provider}/start?invite=I…`
  (PKCE + `state` + `nonce`; invite stashed in a server-side `state`-keyed auth-transaction;
  `__Host-tentura_oauth` cookie binds `state` to the UA) and `GET /api/auth/{provider}/callback`
  (Authorization Code + PKCE exchange; validate ID token `iss/aud/exp/nonce`; read `sub`).
  On success the backend sets the `__Host-tentura_session` cookie — **no seed/token in any URL**.
- **Signup-vs-login at the callback:** look up `(provider, sub)` in `account_credential` →
  not found ⇒ `accept-as-new`; found ⇒ `accept-as-existing`. Invite consumption stays bound to
  **account creation**, independent of credential type.
- `auth_case.dart`: keep `signIn` resolving credential → account (used by the device-key path);
  add OIDC token-validation + WebAuthn challenge/verify behind the backend endpoints above.
- `POST /accounts/me/credentials` (authenticated) links an alt method **after** login, the key
  being generated **in the app origin** for Ed25519. **Conflict policy:** refuse linking a
  `(type, identifier)` already on another account — never auto-merge. **Removal policy:** cannot
  remove the last credential; removing one invalidates sessions minted from it.

### Server — split invite acceptance (preserve beacon-forward)
> The acceptance *logic* below is reused verbatim; only the **trigger** moves — instead of a
> client-supplied EdDSA `authRequestToken`, it is invoked from the **OAuth `/callback`** with
> the invite read from the `state`-keyed transaction (see § Architecture revision).
- `POST /api/v2/invite/:code/accept-as-new` — wraps `createInvited`: signup + friendship
  atomic, **consumes** a slot, and (since `createInvited` already does it) **forwards the
  beacon** when `beaconId != null`. Run **only** when the callback created a new account.
- `POST /api/v2/invite/:code/accept-as-existing` — wraps `accept`/`bindMutual`: befriend
  only, idempotent, **never consumes** a slot, and **forwards the beacon** when present. A
  0-slot code still works for befriend until expired/revoked.
- Rate-limit anonymous signups per IP; invite slots are the natural limiter.

### Landing — real auth (Tier 1) + degraded webview path (Tier 2)
> Revised: the landing is a **preview + auth launcher**, not a session writer. Auth-state is
> probed via a same-site credentialed fetch to the app host; provider CTAs are **top-level
> redirects** to `/api/auth/{provider}/start` (no popup). The session arrives as the
> `__Host-` cookie set by the backend — see § Architecture revision.
- Tier 1 system browsers: Passkey/Google/Apple/Email CTAs → app-host `/api/auth/{provider}/start`;
  on callback the backend sets the session cookie and 302s to the app root.
- Tier 2 webviews: keep the "open in your browser" escape; the recoverable **email** path is the
  eventual Tier-2 method. **Never** offer device-seed signup in a webview (unrecoverable key loss).

### Client (WASM)
- Remove unauthenticated web login UI (`auth_login_screen`, `auth_register_screen` entry);
  unauthenticated → redirect to landing; **read the session from the `__Host-` cookie (BFF)**,
  not from the `#th=` handoff (handoff consume from slice 1 stays only as a fallback).
- Add `Settings > Sign-in methods` (list/add/remove). On web, prefer **redirect-based** OIDC/
  WebAuthn linking (same top-level-redirect pattern as login) over a popup; only if a popup is
  truly required does the COOP constraint (Risk #1) apply — validate empirically then.
- Native apps keep native auth UI.

### Files (representative)
`packages/server/lib/data/database/migration/m0073*.dart` (new) ·
`packages/server/lib/data/repository/user_repository.dart` ·
`packages/server/lib/domain/port/user_repository_port.dart` ·
`packages/server/lib/domain/use_case/auth_case.dart` ·
`packages/server/lib/api/controllers/*` (invite accept + credentials + WebAuthn/OIDC) ·
`packages/server/lib/api/root_router.dart` · `hasura/metadata.json` ·
`packages/client/lib/features/auth/**` · `packages/client/lib/features/settings/**` ·
`packages/landing/**`.

### Acceptance criteria
- Migration applies forward on a copy of prod data, backfilling exactly one device
  credential per user; reversible.
- `signIn` resolves via credential; `accept-as-new` consumes a slot, creates friendship,
  and forwards the beacon when present, atomically; `accept-as-existing` is idempotent,
  never consumes, and forwards the beacon when present.
- Credential conflict refused; last-credential removal blocked; removing a credential
  invalidates its sessions.
- E2E: invite link → landing signup (system browser) → handoff → WASM app authenticated;
  beacon-forward invite results in the beacon appearing for the new friend.
- Server tests under `packages/server/test`; client flows in `packages/client/test`.

---

# PHASE 2 — Intro tour on static HTML before WASM handoff

**Goal.** Show the intro tour instantly as static HTML on the landing while the WASM app
loads in the background; complete the handoff during the tour.

**Prerequisites.** Phase 1 (handoff carries session + onboarding flag).

- Render the tour in `packages/landing`; WASM app honors an "already onboarded" flag from
  the handoff so it does not repeat the tour.
- Files: `packages/landing/**`, client onboarding/guard code in
  `packages/client/lib/features/**`.
- Acceptance: tour renders pre-WASM; not repeated post-handoff; measured TTI improvement.

---

# PHASE 3 (optional) — Deferred deep link / pending-invite pickup

**Goal.** Native app picks up a pending invite on next open (Universal/App Links already
skip the landing when the app is installed).

**Prerequisites.** Phase 1.

- Server tracks an invite "touch"; native app queries pending invite on open and runs the
  matching accept path (carrying beacon-forward).
- Files: `packages/server/**` (touch tracking), native deep-link handling in
  `packages/client/**`.
- Acceptance: install-after-click yields the friendship (and beacon forward) without
  re-clicking.

---

## Risks / Constraints (carry into each phase's detailed plan)

1. **COOP `same-origin` vs popup `postMessage`** (Caddy WASM headers) can break a
   landing↔WASM **popup** handoff for OIDC/WebAuthn linking. **Update (revised model):** both
   the boot handoff *and* login are now **top-level redirects** (fragment redirect in slice 1;
   `/api/auth/{provider}/start` in the revised model) and are *unaffected* by COOP. This risk
   only bites if slice 4 Settings linking uses a **popup** — prefer **redirect-based** linking
   to avoid it entirely. If a popup is unavoidable: relax to `same-origin-allow-popups` on the
   app root or use a dedicated handoff route. **Validate empirically in slice 4.**
2. **iOS in-app webview escape is not programmatic** — accept the explicit user tap as the
   design; do not engineer an escape.
3. **`dev.tentura.io` uses subdomain split** (`app.dev.tentura.io`) — same topology as
   prod; verified in CICD and via `Caddyfile.local` locally, not only on prod hosts.
4. **Hasura coupling** — `users`/credentials schema changes require `hasura/metadata.json`
   regen + permission review, and possibly Ferry `_g` codegen regen.
5. **Migration safety** — `users.public_key` → `account_credentials` backfill must be
   idempotent/reversible; verify via `drift_schemas/` snapshot diffing.
6. **Cross-origin session** — landing and app are **different origins but the same _site_**
   (registrable domain `tentura.io`) on dev (`.dev.tentura.io`) and prod (`.tentura.io`);
   `localStorage` is not shared, but `SameSite=Lax` cookies flow between them and ITP/3p-cookie
   blocking does not apply (see § Architecture revision — do **not** split to a separate
   registrable domain). **Revised model:** the session is a `__Host-` HttpOnly cookie set by
   the app-host backend; the landing detects auth via a same-site credentialed fetch. The
   slice-1 `#th=` fragment handoff (WASM writes its own encrypted secure storage; pinned in
   `docs/handoff-contract.md` + `scripts/check_handoff_contract.sh`) remains only as a
   fallback. **Owed:** live cross-subdomain E2E on the dev stack.
7. **Beacon-forward invites** — when `beaconId` is present, preview + landing must render
   and accept correctly on all surfaces (`/invite/:code` only).

---

## Out of scope / explicitly NOT doing (from the proposal)

- No reliance on Flutter deferred imports for the invite funnel.
- No second Flutter web mini-app.
- No duplicated auth UI in WASM and landing (WASM has no login UI).
- No OAuth/passkey inside in-app webviews.
- No auto-merge of accounts on credential conflict.
