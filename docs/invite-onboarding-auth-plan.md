# Tentura Invite-Link Onboarding & Multi-Credential Auth — Phased Execution Plan

> **How to use this document.** It is a program-level plan split into self-contained
> phases (0→3). Execute one phase per plan-mode session: open this file, read the target
> phase, run that phase's own plan-mode pass to produce line-level steps, build, verify
> against the phase's Acceptance Criteria, then move to the next phase. Phases are ordered
> by dependency; later phases assume earlier ones shipped.

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
device key.

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

**Current invite link format.** `{kServerName}/shared/view?id=<invitationId>` (built at
`forward_beacon_screen.dart:211`; `kPathAppLinkView = '/shared/view'`, `kServerName` in the
shared `lib/consts.dart` — `tentura_root`). The invitation id is the "code" (prefix `'I'`).
Old links must keep working after the new `/invite/:code` scheme lands.

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
- **`app.tentura.io`** — existing Flutter WASM app, **no login UI**; unauthenticated →
  redirect to landing; receives session via same-origin handoff; keeps `Settings >
  Sign-in methods`.
- **Native iOS/Android** — native auth (passkey/Google/Apple SDKs), never the landing;
  same preview endpoint, same UI states, native sheets.
- **Server** — one `accounts` row, many `account_credentials` rows
  (`ed25519_device`, `webauthn`, `oidc:google`, `oidc:apple`, `email_otp`). Invite
  consumption at account creation only.
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
  with the JSON preview. Old `/shared/view?id=I…` links must continue to work.

### Landing — `packages/landing` (static package, implemented)
- Plain static HTML/CSS/JS, served **as-is** — **no build step, no npm, no `node_modules`,
  no bundler**. Caddy serves `{$LANDING_ROOT}` directly. JS libraries only as needed,
  loaded in-browser (CDN ESM or a vendored single file).
- **Runtime config** (`config.js`): `apiBase: ''` (landing host proxies `/api`);
  `appBase` absolute app origin (CI injects `APP_BASE`, default
  `https://app.dev.tentura.io/`). New invite URLs: `/invite/:code` (`I…` id); old
  `/shared/view?id=…` still parsed in `preview.js`.
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

| Variable | Where | Phase 0 dev value | Purpose |
|----------|-------|-------------------|---------|
| `CLIENT_SERVER_NAME` | GitHub `dev` env → `pipeline.yml` `--dart-define=SERVER_NAME` | `https://app.dev.tentura.io` | GraphQL/WS same-origin on app host |
| `SERVER_NAME` | VPS `.env` → Tentura container | `https://dev.tentura.io` | OG tags, Jaspr `/shared/view`, server `kServerName` |
| `APP_BASE` | GitHub `dev` env → CI `sed` on `packages/landing/config.js` | `https://app.dev.tentura.io/` | Landing CTAs → WASM (`appBase`) |
| `APP_HOST` | VPS `.env` → Caddy | `app.dev.tentura.io` | Second TLS site block |

Share links from the app may still point at `CLIENT_SERVER_NAME` (`/shared/view?id=…`);
**both hosts proxy `/shared/*`**, so old and app-origin links keep working. A dedicated
landing share base is optional in Phase 1+.

**CICD / deploy**

- [`pipeline.yml`](../.github/workflows/pipeline.yml): `flutter build web --base-href=/`;
  `CLIENT_SERVER_NAME`; landing tar + `APP_BASE` / `LANDING_SENTRY_DSN` injection.
- [`deploy.sh`](../deploy.sh): extract web + landing **before** `compose up`; placeholder
  `index.html` if `LANDING_DIR` empty.
- [`compose.prod.yaml`](../compose.prod.yaml): mounts `./web`, `./landing`; proxy env
  `APP_HOST`, `APP_ROOT`, `LANDING_ROOT`.

**Deploy prerequisites (ops)**

1. DNS: `app.dev.tentura.io` → VPS (or `*.dev.tentura.io` wildcard).
2. VPS `.env`: `SERVER_NAME=https://dev.tentura.io`, `APP_HOST=app.dev.tentura.io`,
   `APP_ROOT=/srv/web`, `LANDING_ROOT=/srv/landing`, `ACME_EMAIL=…`.
3. GitHub **dev** environment variables: `CLIENT_SERVER_NAME`, `APP_BASE`, `APP_HOST`
   (if referenced), existing `IMAGE_SERVER`, etc.

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

Authoritative key names and cross-subdomain notes: [`docs/handoff-contract.md`](handoff-contract.md).

- Dev/prod are **cross-subdomain** (`dev.tentura.io` ↔ `app.dev.tentura.io`); Phase 1 needs
  `Domain=.dev.tentura.io` / `.tentura.io` cookie or redirect/postMessage transfer.
- CI pin for key strings: **planned**, not wired yet.

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
| OG crawler `/shared/view?id=I…`; old links | **Verify on deploy** |
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

### Server — Drift migration m0073+
- New table `account_credentials(account_id, type, identifier, public_data, created_at, …)`,
  unique index on `(type, identifier)` (OIDC `sub`, WebAuthn credential id, device public
  key). Add migration under `packages/server/lib/data/database/migration/m0073*.dart`.
- Keep `users` as the account row (avoid a physical rename that ripples through Hasura/
  GraphQL — decide in the phase's detailed plan).
- **Data step (idempotent, reversible):** backfill one `ed25519_device` credential per
  existing user from `users.public_key`. Regenerate `drift_schemas/` snapshot and
  **`hasura/metadata.json`**; regenerate Ferry `_g` GraphQL codegen if shapes change.

### Server — auth + credential endpoints
- `auth_case.dart`: `signIn` resolves credential → account → session (instead of
  `getByPublicKey`). Add WebAuthn challenge/verify and OIDC (Google/Apple) token-validation
  paths. Invite consumption stays at **account creation**, independent of credential type.
- `POST /accounts/me/credentials` (authenticated, `verifyBearerJwt`) to link an alt method
  from Settings. **Conflict policy:** refuse linking an OIDC `sub`/credential already on
  another account — never auto-merge. **Removal policy:** cannot remove the last
  credential; removing one invalidates sessions minted from it.

### Server — split invite acceptance (preserve beacon-forward)
- `POST /api/v2/invite/:code/accept-as-new` — wraps `createInvited`: signup + friendship
  atomic, **consumes** a slot, and (since `createInvited` already does it) **forwards the
  beacon** when `beaconId != null`.
- `POST /api/v2/invite/:code/accept-as-existing` — wraps `accept`/`bindMutual`: befriend
  only, idempotent, **never consumes** a slot, and **forwards the beacon** when present. A
  0-slot code still works for befriend until expired/revoked.
- Rate-limit anonymous signups per IP; invite slots are the natural limiter.

### Landing — real auth (Tier 1) + degraded webview path (Tier 2)
- Tier 1 system browsers: Passkey/Google/Apple/Email; on success write the session via the
  Phase-0 handoff contract; redirect to the app root.
- Tier 2 webviews: degraded email/Ed25519 signup → account with a single device
  credential; email the user to add a stronger method later in a real browser.

### Client (WASM)
- Remove unauthenticated web login UI (`auth_login_screen`, `auth_register_screen` entry);
  unauthenticated → redirect to landing; read session from handoff.
- Add `Settings > Sign-in methods` (list/add/remove). On web, linking opens a landing
  popup for OIDC/WebAuthn then `postMessage` back — **subject to the COOP constraint
  (Risks);** validate empirically before committing to popups.
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

1. **COOP `same-origin` vs popup `postMessage`** (Caddy WASM headers) can break the
   landing↔WASM popup handoff for OIDC/WebAuthn linking. Options: relax to
   `same-origin-allow-popups` on the app root, use redirect-based OIDC, or a dedicated
   handoff route. **Validate empirically early in Phase 1.**
2. **iOS in-app webview escape is not programmatic** — accept the explicit user tap as the
   design; do not engineer an escape.
3. **`dev.tentura.io` uses subdomain split** (`app.dev.tentura.io`) — same topology as
   prod; verified in CICD and via `Caddyfile.local` locally, not only on prod hosts.
4. **Hasura coupling** — `users`/credentials schema changes require `hasura/metadata.json`
   regen + permission review, and possibly Ferry `_g` codegen regen.
5. **Migration safety** — `users.public_key` → `account_credentials` backfill must be
   idempotent/reversible; verify via `drift_schemas/` snapshot diffing.
6. **Cross-origin session** — landing and app are on **different subdomains** on both dev
   (`.dev.tentura.io`) and prod (`.tentura.io`). localStorage is not shared; handoff keys
   are pinned in `docs/handoff-contract.md`; Phase 1 must implement cookie or transfer.
   CI pin for key names is planned.
7. **Link compatibility** — old `/shared/view?id=I…` links must keep resolving after the
   new `/invite/:code` scheme; beacon-forward invites (`beaconId` present) must render and
   accept correctly on all surfaces.

---

## Out of scope / explicitly NOT doing (from the proposal)

- No reliance on Flutter deferred imports for the invite funnel.
- No second Flutter web mini-app.
- No duplicated auth UI in WASM and landing (WASM has no login UI).
- No OAuth/passkey inside in-app webviews.
- No auto-merge of accounts on credential conflict.
