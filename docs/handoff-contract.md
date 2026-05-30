# Landing ↔ WASM-app session handoff contract

> **Phase 0 deliverable: the contract is *defined and pinned* here now; it is
> *exercised* (written by the landing, read by the WASM app) in Phase 1.** This
> doc is the single source of truth for the storage keys so `packages/landing`
> and the Flutter WASM app at `app.tentura.io` cannot drift. A CI check pins it
> (see "CI pin" below).

## Origin / scope

The handoff works only when the landing and the WASM app share a storage origin:

- **prod:** landing `tentura.io`, app `app.tentura.io` — localStorage is
  **per-origin** (not shared across subdomains). Phase 1 handoff needs a cookie
  scoped to `Domain=.tentura.io` **or** a one-time postMessage/redirect transfer
  (gated by COOP on the app host, Risk #1). Phase 0 only fixes the *key names
  and value formats* below.
- **dev (subdomain split, mirrors prod):** landing `dev.tentura.io`, app
  `app.dev.tentura.io` — also cross-origin; use `Domain=.dev.tentura.io` (or
  equivalent transfer) in Phase 1, same as prod.
- **local simulation:** `dev.lvh.me:9080` + `app.dev.lvh.me:9080` via
  `Caddyfile.local` (or `dev.tentura.test` / `app.dev.tentura.test` with
  `/etc/hosts`) — cross-subdomain for cookie/handoff testing.

## Keys (authoritative)

These mirror exactly what the WASM app already reads/writes via
`LocalSecureStorage`
(`packages/client/lib/features/auth/data/repository/auth_local_repository.dart`):

| Key | Value | Notes |
|---|---|---|
| `Auth:currentAccountId` | current user id (`String`, e.g. `U…`) | which account is active |
| `Auth:Id:{userId}` | account seed — **base64url, 32 bytes** | one entry per known account; `{userId}` is the `U…` id |

Key prefix is `Auth` (`_repositoryKey`); the current-account key is
`Auth:currentAccountId` (`_currentAccountKey`); per-account seed keys are
`Auth:Id:{id}` (`_getAccountKey`). **Do not rename** without updating both this
doc and the WASM app, or the handoff silently breaks.

## Direction of flow (Phase 1)

1. Landing completes auth (device-seed / passkey / OIDC / email).
2. Landing writes `Auth:Id:{userId}` (seed) and `Auth:currentAccountId`.
3. Landing redirects to the app root (`app.tentura.io` / `app.dev.tentura.io`).
4. WASM app boots, `AuthCubit` hydrates from these keys, lands authenticated —
   no web login UI.

## CI pin

A CI check asserts these key strings stay in sync between the two sides
(landing source constant ↔ the `auth_local_repository.dart` constants). If the
key names diverge, CI fails. This prevents the most likely drift bug
(Risk #6) before it reaches a deploy.
