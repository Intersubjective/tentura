# Landing ↔ WASM-app session handoff contract

> **The contract is *defined and pinned* here; it is *exercised* (written by the
> landing, read by the WASM app) in Phase 1, slice 1.** This doc is the single
> source of truth for the handoff payload so `packages/landing` and the Flutter
> WASM app at `app.tentura.io` cannot drift. A CI check pins it (see "CI pin").

## Origin / scope

The landing and the WASM app are on **different subdomains**, so storage is **not**
shared between them:

- **prod:** landing `tentura.io`, app `app.tentura.io`.
- **dev (subdomain split, mirrors prod):** landing `dev.tentura.io`, app
  `app.dev.tentura.io`.
- **local simulation:** `dev.lvh.me:9080` + `app.dev.lvh.me:9080` via
  `Caddyfile.local` (or `dev.tentura.test` / `app.dev.tentura.test` with
  `/etc/hosts`).

Because the origins differ, the landing **cannot** write into the app's storage
directly.

## Why the landing does NOT write the app's storage keys

An earlier draft of this contract had the landing write `Auth:Id:{userId}` and
`Auth:currentAccountId` straight into the app's `localStorage`. **That is not
implementable**, for two independent reasons:

1. **Cross-origin.** `localStorage` is per-origin; the landing origin cannot
   touch the app origin's `localStorage` at all.
2. **The app's storage is encrypted and namespaced.** The app stores secrets via
   `LocalSecureStorage`
   (`packages/client/lib/data/service/local_secure_storage.dart`), which wraps
   `flutter_secure_storage`. Its web backend AES-GCM-**encrypts every value** and
   **prefixes every key** with a `publicKey` namespace. A plaintext seed dropped
   into `localStorage` would be unreadable by the app.

So the app's storage keys (`Auth:currentAccountId`, `Auth:Id:{userId}`) are
**app-internal** and written only by `AuthLocalRepository` — never by the
landing. The handoff instead transfers a **plaintext payload** that the app
itself writes through `AuthLocalRepository.addAccount` /
`setCurrentAccountId`, so encryption + key-prefixing are correct by
construction.

## Transport: one-time URL fragment

The landing redirects (top-level navigation) to the app root with the payload in
the **URL fragment**:

```
{appBase}#th=<base64url( utf8( JSON ) )>
```

- The **fragment** (not the query) carries the secret: fragments are never sent
  in the HTTP request, so the seed stays out of Caddy/Hasura access logs.
- A top-level navigation with a fragment is **unaffected by the app host's COOP
  `same-origin` / COEP headers** (COOP only restricts cross-origin *window
  references* / `postMessage` popups — that constraint applies to the later
  Settings credential-linking popup, not this boot handoff).
- The app **scrubs** the fragment immediately (see flow below).

### Payload (canonical field names — CI-pinned)

JSON, then UTF-8 → base64url:

```json
{ "v": 1, "userId": "U…", "seed": "<base64url 32-byte seed>", "displayName": "optional" }
```

<!-- HANDOFF-CONTRACT-PIN (do not edit casually — scripts/check_handoff_contract.sh
     asserts this exact set in handoff.js and web_handoff_web.dart too):
     key=th v userId seed displayName -->

| Field | Meaning |
|---|---|
| `th` (fragment key) | names the handoff parameter in the fragment |
| `v` | payload version (currently `1`); app rejects unknown majors |
| `userId` | account id (`U…`) |
| `seed` | base64url-encoded 32-byte account seed (same format as `AuthCase.signUp`) |
| `displayName` | optional; may contain non-ASCII (see encoding note) |

**Encoding note.** The landing must encode UTF-8 → base64 (`displayName` can be
Cyrillic/accented). Bare `btoa(json)` throws on non-ASCII; use
`btoa(unescape(encodeURIComponent(json)))` then the base64url transform. The app
decodes symmetrically (`utf8.decode(base64Url.decode(base64.normalize(...)))`).

## Direction of flow (Phase 1)

1. Landing completes auth (device-seed / passkey / OIDC / email) and obtains the
   account `{ userId, seed, displayName? }`. *(Producing the seed is slice 3; the
   transport is slice 1.)*
2. Landing builds `{appBase}#th=<payload>` (`packages/landing/handoff.js`
   `buildHandoffUrl` / `redirectToApp`) and **redirects** to the app root.
3. The app captures the raw fragment into `window.__tenturaHandoff` in an inline
   `web/index.html` script **before** Flutter boots (the app uses the hash URL
   strategy, which would otherwise normalize the fragment away during engine
   init), and scrubs it from the address bar.
4. On boot, `AuthCubit.hydrated` calls `AuthCase.consumeHandoff()`
   (`packages/client/lib/features/auth/data/service/web_handoff_web.dart` reads
   and decodes the captured fragment): it writes the account via
   `AuthLocalRepository.addAccount` + `setCurrentAccountId` (idempotent if the
   account already exists), then `scrubHandoff()`.
5. Normal hydration finds the account and signs in — the app lands
   authenticated, no web login UI.

A malformed/absent handoff is ignored and never blocks boot.

## App-internal storage keys (written by the app only)

These mirror what the WASM app reads/writes via `LocalSecureStorage`
(`packages/client/lib/features/auth/data/repository/auth_local_repository.dart`)
and are listed here for reference — **the landing never writes them**:

| Key | Value |
|---|---|
| `Auth:currentAccountId` | current account id (`U…`) |
| `Auth:Id:{userId}` | account seed (encrypted + key-prefixed by the secure-storage backend) |

## CI pin

`scripts/check_handoff_contract.sh` (run in CI) asserts the canonical field-name
set (`key=th v userId seed displayName`) appears verbatim in **all three** of:

- `packages/landing/handoff.js`
- `packages/client/lib/features/auth/data/service/web_handoff_web.dart`
- this document

If any side renames a field, CI fails — preventing the most likely drift bug
(Risk #6) before it reaches a deploy.
