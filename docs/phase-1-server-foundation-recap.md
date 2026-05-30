# Phase 1 — Server-foundation slice: recap & follow-up guide

> Companion to [`invite-onboarding-auth-plan.md`](invite-onboarding-auth-plan.md).
> This is what **shipped** in the server-foundation slice and what the **next
> slices** need. Read this before continuing Phase 1.

**Branch / commit:** `feat/phase-1-account-credentials` — `feat(phase-1): multi-credential
auth model + split invite accept endpoints` (17 files). Not yet merged or pushed.

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

## Follow-up slices (ordered; each its own plan-mode pass)

1. **Cross-subdomain session handoff (do this next — highest technical risk).**
   Landing and app are different subdomains on dev (`dev.` ↔ `app.dev.`) and prod.
   Implement the handoff per [`handoff-contract.md`](handoff-contract.md) — `Domain=.tentura.io`
   cookie or one-time redirect/postMessage. **Validate the COOP `same-origin` vs popup
   constraint empirically first** (plan Risk #1): the app host sets COOP/COEP, which can
   break a popup `postMessage`. Decide redirect-based vs `same-origin-allow-popups` before
   building. Wire the CI pin for the handoff key names (planned, not done).
2. **Credential providers + `/accounts/me/credentials`.** Add WebAuthn challenge/verify,
   OIDC (Google/Apple) token validation, email-OTP — each resolves/creates an
   `account_credential` row; invite consumption stays at account creation. Authenticated
   `POST /accounts/me/credentials` (link) with **conflict policy** (refuse a sub/cred
   already on another account, never auto-merge) and **removal policy** (can't remove the
   last; removal invalidates that credential's sessions). Needs external setup (OAuth
   client IDs, WebAuthn RP config).
3. **Landing real auth (Tier 1) + degraded webview path (Tier 2).** Flip `AUTH_ENABLED`
   in `packages/landing/main.js`; on success write the handoff and redirect to the app.
   Tier 2 = degraded email/device-seed signup. Static, no npm (see landing constraints).
4. **Client WASM.** Remove the web login UI (`auth_login_screen`/`auth_register_screen`
   entry), redirect unauthenticated → landing, hydrate from the handoff. Add
   `Settings > Sign-in methods` (list/add/remove) — linking opens a landing popup, subject
   to the COOP constraint from slice 1.
5. **(Optional) non-deleting slot / multi-use invite model** — enables truly idempotent
   `accept-as-existing` and 0-slot befriend-until-expired. Schema change (`m00NN`).

## Key files (this slice)
`packages/server/lib/data/database/migration/m0080.dart` ·
`…/table/account_credentials.dart` · `…/domain/entity/account_credential_entity.dart` ·
`…/data/repository/user_repository.dart` · `…/domain/use_case/auth_case.dart` ·
`…/domain/use_case/invitation_case.dart` · `…/api/controllers/invite_accept_{new,existing}_controller.dart` ·
`…/api/root_router.dart` · tests under `…/test/domain/use_case/`.
