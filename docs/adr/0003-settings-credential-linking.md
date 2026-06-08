# ADR 0003: Settings credential linking (strict link-mode)

## Status

Accepted — 2026-06-08

## Context

Phase 3 adds "link Google / email / recovery seed" from Settings. Login/signup
uses `CredentialAuthCase.resolveOrCreate`, which may switch accounts or create
new ones. Settings linking must **never** switch or mint a session — it only
attaches a new `account_credential` row to the **current** authenticated
account.

## Decision

### Strict-link primitive

`UserRepository.linkCredentialToAccountStrict`:

- Idempotent when `(type, identifier)` is already on **this** account.
- `CredentialConflictException` (409) when the credential is owned elsewhere.
- `ContactConflictException` (409) when an authoritative verified contact is
  owned elsewhere.
- No auto-merge, no `resolveOrCreate`.

### Transport

| Method | Client | Server |
|--------|--------|--------|
| Recovery seed | Generate Ed25519 seed → `POST /accounts/me/credentials` `{authRequestToken}` | `CredentialCase.linkDevice` → strict-link `ed25519_device` |
| Google native | `google_sign_in` id token → `POST /accounts/me/credentials/google` | `verifyGoogleIdToken` (nonce optional) → strict-link `oidc:google` |
| Google web | Bearer `POST /auth/google/link/intent` → top-level nav to `link/start?lt=` → OAuth callback | OAuth state carries `linkAccountId`; callback strict-links, **no** `createSession` |
| Email | `POST /auth/email/link/start` `{email}` | Transaction stores `link_account_id`; verify strict-links `email_otp` + contact, static success page |

### Session safety

Link branches fork **before** the login tail that calls `createSession` in
`auth_google_controller` and `auth_email_controller`. Google web `lt` is
Bearer-minted; `link/start` additionally requires a matching
`__Host-tentura_session` cookie.

### Per-credential session revoke

Access JWTs carry a `cid` claim (credential id). `account_session.credential_id`
is set at session creation. `removeCredential` revokes sessions for that
credential inside the existing `FOR UPDATE` transaction before deleting the row.

### Native scope

Native Settings always runs on seed-backed accounts (Bearer available). A
web-only Google/email account reaches native only after linking a recovery seed
on web and using "recover from seed" on native.

## Consequences

- Cross-account credential/contact conflicts surface as 409; no silent merge.
- Outstanding Bearer JWTs after credential removal still expire (~1h); accepted.
- iOS Google id tokens use a separate OAuth client id (`GOOGLE_IOS_CLIENT_ID`)
  in the server `aud` allow-list.
