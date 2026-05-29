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
**`dev.tentura.io`** is the **CICD-default deploy** and must be supported — today it is a
**single host** serving everything; the landing/app split must work there too (see Phase 0,
Routing).

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

**Routing today (one host).** `Caddyfile`:
- `{$SERVER_NAME}` serves the Flutter SPA at root (`root * /srv/web`, `try_files …
  /index.html`); `/api/v1/graphql` → Hasura; `/api/v2/graphql`, `/api/v2/ws`,
  `/api/v2/room-attachments/*`, `/shared/*`, `firebase-messaging-sw.js` → Dart server
  (`tentura:2080`).
- SPA handler sets WASM headers: `Cross-Origin-Opener-Policy: same-origin`,
  `Cross-Origin-Embedder-Policy: credentialless`. **These interact with the handoff** —
  COOP `same-origin` can sever `window.opener`, breaking landing↔WASM popup
  `postMessage` (see Risks).

**Optional auth middleware exists.** `packages/server/lib/api/middleware/auth_middleware.dart`:
`extractJwtClaims` (non-failing; on the GraphQL endpoint) vs `verifyBearerJwt` (failing).
The preview endpoint needs the **non-failing** variant.

**Client auth/invite surface.** `packages/client/lib/features/auth/` (`auth_cubit.dart`
@singleton/preResolve, `auth_local_repository.dart` seed storage, `auth_login_screen.dart`,
`auth_register_screen.dart`); `packages/client/lib/features/invitation/`.

---

## Target Architecture (high level)

- **`tentura.io`** — new static HTML/JS landing (**`packages/landing`**, monorepo). All
  invite + web-auth flows. 300–800ms TTI; works in webviews; OG previews; OAuth redirect
  URIs; native WebAuthn in DOM; in-app-browser detection. `@noble/ed25519` for JS Ed25519;
  **no third-party scripts**.
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

### Server — preview endpoint (JSON, REST on `root_router`)
- Add `GET /api/v2/invite/:code/preview` to
  `packages/server/lib/api/root_router.dart`, guarded by `_authMiddleware.extractJwtClaims`
  (non-failing) so anonymous vs existing-user is distinguishable.
- New controller `packages/server/lib/api/controllers/invite_preview_controller.dart`
  returning:
  ```
  { inviter:{id,displayName,image}, codeStatus, callerStatus, beacon?, suggestedAction }
  ```
  - `codeStatus`: available | consumed | expired | revoked (reuse
    `InvitationEntity.isAccepted` / `isExpired`; add revoked if/when modeled).
  - `callerStatus`: anonymous | existing-user | already-friends | is-inviter
    (self-invite blocked).
  - `beacon`: present iff `invitation.beaconId != null` — surface beacon title/snippet so
    the landing can render "Alice shared <beacon> with you".
- Extend `InvitationCase` with a read-only `preview(...)` that computes the above; add an
  "is caller already mutual-friend of issuer?" check to `InvitationCase` /
  `UserRepositoryPort` (read-only).
- **OG meta stays on the existing Jaspr path** (`shared_view_controller` +
  `invitation_view_component`) for Telegram/iMessage crawlers; keep its output consistent
  with the JSON preview. Old `/shared/view?id=I…` links must continue to work.

### Landing — `packages/landing` (new static package)
- Plain static HTML/JS, no shipped framework runtime; build emits a static dir.
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
- Funnel analytics (Sentry/PostHog) firing **before** any WASM — a first-class Phase 0
  deliverable.

### Infra — routing for prod AND dev
- Add a `tentura.io` (landing static) vs `app.tentura.io` (existing SPA + `/api/*`) host
  split in `Caddyfile`; serve `packages/landing` build output at the apex.
- **`dev.tentura.io` is single-host (CICD default).** Parameterize the split so dev works:
  decide between (a) **path-based on dev** (`dev.tentura.io/` = landing, `dev.tentura.io/app/`
  = WASM app — keeps a single origin, simplest handoff) vs (b) **subdomain on dev**
  (`app.dev.tentura.io`, needs cookie scoped to `.tentura.io`). Recommend **path-based on
  dev, subdomain on prod**, both driven by Caddy env (`LANDING_ROOT`, `APP_ROOT`). Wire
  the landing build into `deploy.sh` / `compose.prod.yaml` and the CICD pipeline.
- Keep WASM `COOP/COEP` headers scoped to the **app** root only.

### Handoff contract (define now; exercised in Phase 1)
- Same-origin / `.tentura.io`-scoped session+seed keys in localStorage; **document exact
  key names**; pin the schema in CI so `packages/landing` and the WASM app cannot drift.

### Files (representative)
`packages/landing/**` (new) · `packages/server/lib/api/root_router.dart` ·
`packages/server/lib/api/controllers/invite_preview_controller.dart` (new) ·
`packages/server/lib/domain/use_case/invitation_case.dart` ·
`packages/server/lib/domain/port/{invitation,user}_repository_port.dart` ·
`Caddyfile` · `deploy.sh` · `compose.prod.yaml` · CICD config.

### Acceptance criteria
- `curl GET /api/v2/invite/:code/preview` returns correct `codeStatus`/`callerStatus` for
  anonymous, existing-user, already-friends, is-inviter, expired; and includes `beacon`
  when the invite carries a `beaconId`.
- Crawler UA still gets OG HTML; browser UA behavior preserved; old `/shared/view?id=I…`
  links still resolve.
- Landing renders all five states + beacon overlay; TTI measured in a throttled mobile
  webview; funnel events visible in analytics **before** WASM.
- Caddy split verified on **both** prod (apex vs `app.`) and `dev.tentura.io`.

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
3. **`dev.tentura.io` is single-host** — the landing/app split must be parameterized
   (path-based on dev recommended) and verified in CICD, not just on prod.
4. **Hasura coupling** — `users`/credentials schema changes require `hasura/metadata.json`
   regen + permission review, and possibly Ferry `_g` codegen regen.
5. **Migration safety** — `users.public_key` → `account_credentials` backfill must be
   idempotent/reversible; verify via `drift_schemas/` snapshot diffing.
6. **Cross-origin session** — cookie/localStorage scoping across `.tentura.io` (and the
   dev host) must be exact, documented, and CI-pinned to prevent landing↔app drift.
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
