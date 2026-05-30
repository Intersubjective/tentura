# Phase 1 — Server-foundation slice: recap & follow-up guide

> Companion to [`invite-onboarding-auth-plan.md`](invite-onboarding-auth-plan.md).
> This is what **shipped** in the server-foundation slice and what the **next
> slices** need. Read this before continuing Phase 1.

**Branch:** `feat/phase-1-account-credentials` (not yet merged or pushed). Shipped so far:
1. `feat(phase-1): multi-credential auth model + split invite accept endpoints` (17 files).
2. Cross-subdomain session handoff (slice 1 below) — landing→app via URL fragment.
   **Working tree, not yet committed.**

---

## What shipped (server-only, on the existing Ed25519 credential)

- **`account_credential` table** (`m0080`): `id, account_id→user ON DELETE CASCADE,
  type, identifier, public_data jsonb, created_at`; unique `(type, identifier)`;
  index on `account_id`. Idempotent backfill of one `ed25519_device` credential per
  user from `user.public_key`. `public_key` is **kept and dual-written** (reversible,
  no Hasura ripple). Table is **server-internal** (untracked in Hasura).
  - Drift table `table/account_credentials.dart` + entity/`CredentialType` enum
    (`entity/account_credential_entity.dart`); registered in `tentura_db.dart`
    (table list **and** entity import — Drift copies `clientDefault` into `.g.dart`).
- **Auth via credential:** `AuthCase.signIn` → `UserRepository.getByCredential('ed25519_device', publicKey)`
  (was `getByPublicKey`). New `AuthCase.signUpWithInvite` takes the invite code from
  the **URL**. `create()`/`createInvited()` dual-write the device credential.
- **Split invite accept (REST, additive — GraphQL mutations stay):**
  - `POST /api/v2/invite/:code/accept-as-new` — anonymous; body `{authRequestToken,
    displayName, handle?}`; returns oauth2 session map. Wraps `signUpWithInvite`.
  - `POST /api/v2/invite/:code/accept-as-existing` — `verifyBearerJwt`; befriend only.
  - Both preserve the existing **beacon-forward**.

## Gotchas the next session must know

- **Drift does NOT own the schema.** `enableMigrations: false`, `schemaVersion = 1`,
  `drift_schemas/tentura/` empty. Raw "migrant" SQL in `migration/m0001…mNNNN.dart`
  (registered in `_migrations.dart`: `part` line **and** `InMemory([...])` list) is the
  schema; applied at boot by `migrateDbSchema()`. Adding a table = Drift class +
  register + `build_runner build -d` + raw SQL migration. **No** drift-schema snapshot
  to regen (the plan doc is wrong on that). `m0080` is the **next** number was 0080 (plan
  said m0073 — repo had already reached m0079).
- **`.g.dart` / `.config.dart` are gitignored**, rebuilt at deploy; `.mocks.dart` is
  tracked. After changing DI/tables run `build_runner build -d`; if injectable shows
  "no-op" and misses new `@Injectable`s, run `build_runner clean` then build.
- **All `UserRepositoryPort` implementers must stay in sync:** real
  (`data/repository/user_repository.dart`), DI mock (`data/repository/mock/user_repository_mock.dart`),
  test stub (`test/domain/evaluation/evaluation_graph_test_repos.dart`), and the mockito
  mock (regenerated). Adding a port method breaks the latter three at compile time.
- **`accept-as-existing` is single-use, not idempotent.** `bindMutual` deletes the
  invite row, so a *repeat* of a succeeded befriend returns **404** (issuer unknown on
  retry). The landing should treat 404 as "already accepted". True idempotency needs the
  deferred slot model.

## Owed before this slice is "done in prod"

- **Live curl matrix on the dev stack** (anonymous / issuer JWT / friend / stranger /
  consumed / expired / invalid / beacon invite) — needs the dev deploy prereqs (DNS for
  `app.dev.tentura.io`, VPS `.env`, GitHub `dev` env vars; see plan Phase 0 § Infra).
- Local m0080 + Drift path were verified against a throwaway Postgres during the build
  (passed); that script was not committed.

---

## What shipped — slice 1: cross-subdomain session handoff (client + landing)

Transport-only (the auth that *produces* the seed is slice 3). **The pinned
`handoff-contract.md` model was wrong** — it had the landing write the app's localStorage
keys directly. Two blockers, both verified: (a) cross-origin (landing can't touch the app
origin's localStorage); (b) the app's `LocalSecureStorage` (`flutter_secure_storage` web)
**AES-GCM-encrypts values and key-prefixes them**, so a plaintext seed would be unreadable.
`handoff-contract.md` was **rewritten** to the model below.

- **Transport = URL fragment, decision locked with user.** Landing redirects to
  `{appBase}#th=<base64url(utf8(json))>`, payload `{v:1, userId, seed, displayName?}`. The
  **app itself** writes via `AuthLocalRepository.addAccount`/`setCurrentAccountId` (correct
  encryption/prefix by construction). Fragment never hits the server/logs.
- **COOP is NOT a blocker here.** A top-level redirect + `#fragment` is unaffected by the
  app host's COOP `same-origin` — that gate (plan Risk #1) applies to the **slice-4 Settings
  popup**, not the boot handoff. So slice 1 did **not** wait on the popup experiment.
- **Hash-strategy hazard (the real one).** The client sets **no** URL strategy → Flutter web
  uses the **hash strategy**, so `#th=…` would be clobbered during engine init *and* the
  app's own routes live in the fragment (`#/home/...`). Fix: an inline `web/index.html`
  script captures+scrubs **only when the hash starts with `#th=`** (route fragments pass
  through), stashing into `window.__tenturaHandoff` **before** `flutter_bootstrap.js`.
  `web_handoff_web.dart` reads that global (not live `location.hash`).
- **App consume:** `AuthCubit.hydrated` calls `AuthCase.consumeHandoff()` as its first line
  (before `getAccountsAll`); `consumeHandoff` → `applyHandoff` (idempotent: skips insert if
  account exists) → always `scrubHandoff()`; malformed/absent handoff never blocks boot.
- **CI pin (was "planned, not done" — now wired):** `scripts/check_handoff_contract.sh`
  asserts `th/v/userId/seed/displayName` stay in sync across `handoff.js`, `handoff_codec.dart`,
  and `handoff-contract.md`; runs in `pipeline.yml`.
- **Verified:** 11 client unit tests (codec + `applyHandoff` idempotency); `dart analyze`
  clean; `flutter build web` compiles the js_interop path; CI-pin negative path confirmed.
- **Owed (needs dev stack / real browser):** live cross-subdomain E2E on `Caddyfile.local`
  — fragment survives capture-before-boot, boots authenticated, scrub holds, and a
  `#/home/...` refresh still lands on that route (not root — the scrub-gate discriminator).

### Gotchas (slice 1)
- **Don't ungate the scrub.** Stripping any `#` breaks refresh/deep-links under the hash
  strategy. Keep it `#th=`-only.
- **Reader source is the captured global, not `location.hash`** — by the time Dart runs,
  Flutter has already normalized the live hash.
- **`btoa` throws on non-ASCII** — landing uses `btoa(unescape(encodeURIComponent(json)))`;
  app decodes UTF-8-aware. Non-ASCII `displayName` is covered by a roundtrip test.
- **Known state:** if `signIn` fails after the handoff wrote the account+seed, `hydrated`
  resets `currentAccountId` but the local row+seed persist (stale-account next boot).
  Acceptable for slice 1; cleanup belongs with slice 2/3 account lifecycle.

### Key files (slice 1)
`packages/client/web/index.html` · `…/features/auth/data/service/{handoff_payload,handoff_codec,web_handoff,web_handoff_stub,web_handoff_web}.dart` ·
`…/features/auth/domain/use_case/auth_case.dart` · `…/features/auth/ui/bloc/auth_cubit.dart` ·
`…/test/features/auth/handoff_test.dart` · `packages/landing/{handoff.js,handoff-dev.html,README.md}` ·
`scripts/check_handoff_contract.sh` · `.github/workflows/pipeline.yml` · `docs/handoff-contract.md`.

---

## What shipped — slice 2: credential management (server-only, infra + `ed25519_device`)

Scoped with the user: build the reusable **infrastructure + the `ed25519_device` provider**
only; externally-gated providers (WebAuthn, OIDC, email-OTP) and immediate session
revocation are deferred to follow-up slices.

- **Three REST endpoints**, all guarded by `verifyBearerJwt`, account = `jwt.sub`:
  - `GET /api/v2/accounts/me/credentials` — list the caller's credentials.
  - `POST /api/v2/accounts/me/credentials` — body `{authRequestToken}`; verifies the EdDSA
    auth-request (proves possession of a new device key) and links an `ed25519_device`
    credential. Conflict → **409**.
  - `DELETE /api/v2/accounts/me/credentials/<credentialId>` — remove; last one → **409**,
    unknown id → **404**.
- **`CredentialCase`** (`domain/use_case/credential_case.dart`) wraps the repo; reuses the
  new public `AuthCase.verifyDeviceAuthRequest(token)` for the link path.
- **Repo (`UserRepository`)** gained `listCredentials` / `addCredential` / `removeCredential`
  on `UserRepositoryPort`. **Conflict** is the DB's job: the `m0080` unique
  `(type, identifier)` index throws `UniqueViolationException` → mapped to
  `CredentialConflictException` (no racy pre-check). **Removal** runs inside a transaction
  that `SELECT … FOR UPDATE`-locks the account's credential rows, then enforces the
  last-credential guard — so two concurrent removals of different rows can't both win and
  leave the account with none.
- **No migration:** the `account_credential` table already exists (m0080).
- **Verified:** 5 new `CredentialCase` unit tests; full server suite (144) green; `dart
  analyze` clean; both Caddyfiles `caddy validate` OK.

### Gotchas (slice 2)
- **Caddy catch-all.** The `(api)` snippet sends everything under `/api/*` to **Hasura**
  except an explicit allowlist. A new `handle /api/v2/accounts/*` → Tentura block was added
  to **both** `Caddyfile` and `Caddyfile.local`; without it the endpoint is unreachable in
  deploy while every server test still passes (tests hit the router directly).
- **FK column filter.** `account_credential.account_id` is a Drift *reference* column, so
  the manager filter is `e.accountId.id(value)` (a join to `user.id`), not
  `e.accountId(value)` — the latter does not compile.
- **Session revocation is OWED.** `parseAndVerifyJwt` is signature-only and `_issueJwt`
  records no credential id; removing a credential does **not** kill its live sessions. The
  1h JWT expiry (`kJwtExpiresIn`) is the interim mitigation. Honoring the acceptance
  criterion needs a `cid` claim + a per-credential revocation/version check on the hot auth
  path — deferred (no client consumes removal until slice 4 Settings).

### Key files (slice 2)
`packages/server/lib/domain/use_case/credential_case.dart` (new) ·
`…/api/controllers/account_credentials_controller.dart` (new) ·
`…/domain/port/user_repository_port.dart` · `…/data/repository/user_repository.dart` ·
`…/data/repository/mock/user_repository_mock.dart` · `…/domain/use_case/auth_case.dart` ·
`…/domain/exception.dart` · `…/domain/exception_codes.dart` · `…/api/root_router.dart` ·
`…/test/domain/use_case/credential_case_test.dart` (new) ·
`…/test/domain/evaluation/evaluation_graph_test_repos.dart` · `Caddyfile` · `Caddyfile.local`.

---

## Follow-up slices (ordered; each its own plan-mode pass)

1. ✅ **Cross-subdomain session handoff — SHIPPED (transport).** Implemented as a URL-fragment
   redirect (not a cookie/popup); see "What shipped — slice 1" above and the rewritten
   [`handoff-contract.md`](handoff-contract.md). CI pin wired. **Owed:** live cross-subdomain
   E2E on the dev stack. The COOP/popup question deferred to slice 4 (Settings linking).
2. ✅ **Credential management infrastructure + `/accounts/me/credentials` — SHIPPED (infra
   + `ed25519_device`).** Authenticated link/list/remove with **conflict policy** (unique
   `(type, identifier)` → 409, never auto-merge) and **removal policy** (can't remove the
   last → 409). See "What shipped — slice 2" below. **Deferred to follow-up slices** (scoped
   with the user — each needs external setup): the concrete providers (WebAuthn
   challenge/verify, OIDC Google/Apple token validation, email-OTP) and **immediate session
   revocation on removal** (JWTs are stateless, 1h expiry is the interim mitigation).
3. **Landing real auth (Tier 1) + degraded webview path (Tier 2).** Flip `AUTH_ENABLED`
   in `packages/landing/main.js`; on success call `redirectToApp({userId, seed, displayName})`
   from the **already-built** `packages/landing/handoff.js` (slice 1). Tier 2 = degraded
   email/device-seed signup. Static, no npm (see landing constraints).
4. **Client WASM.** Remove the web login UI (`auth_login_screen`/`auth_register_screen`
   entry), redirect unauthenticated → landing, hydrate from the handoff (the consume side
   from slice 1 is done). Add `Settings > Sign-in methods` (list/add/remove) — linking opens
   a landing popup. **This is where the COOP `same-origin` vs popup `postMessage` constraint
   (plan Risk #1) must be validated empirically** — it did not affect the slice-1 redirect.

## Key files (this slice)
`packages/server/lib/data/database/migration/m0080.dart` ·
`…/table/account_credentials.dart` · `…/domain/entity/account_credential_entity.dart` ·
`…/data/repository/user_repository.dart` · `…/domain/use_case/auth_case.dart` ·
`…/domain/use_case/invitation_case.dart` · `…/api/controllers/invite_accept_{new,existing}_controller.dart` ·
`…/api/root_router.dart` · tests under `…/test/domain/use_case/`.
