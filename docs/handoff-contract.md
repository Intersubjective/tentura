# Landing ↔ WASM-app session handoff contract

> **Scope:** `#th=` fragment handoff for **device-seed signup only**. Email magic
> link and Google OAuth set `__Host-tentura_session` and do **not** use this
> transport. The payload field names are CI-pinned (see "CI pin").
>
> Broader auth/onboarding status: [`invite-onboarding-auth-plan.md`](invite-onboarding-auth-plan.md).

## Origin / scope

Production and dev use a **single public origin** for landing and WASM
(`tentura.io`, `dev.tentura.io`, local `dev.lvh.me:9443`). `resolve_app_base.js`
defaults `appBase` to `location.origin` when unset.

Legacy subdomain split (`app.tentura.io`) may still be configured via explicit
`appBase` in `config.js` for rollback — the handoff mechanics are unchanged.

Regardless of same- vs cross-origin deploy, the landing **cannot** write the
app's encrypted `LocalSecureStorage` keys directly — only a one-time fragment
payload the app consumes on boot.

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

## Direction of flow (device-seed only)

1. Landing completes **device-seed signup** (`auth.js` `signUpWithSeed`) and
   obtains `{ userId, seed, displayName? }` from `accept-as-new`.
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
