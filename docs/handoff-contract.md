# Landing ↔ WASM-app session handoff contract (retired)

> **Status: RETIRED (2026-06).** Web landing no longer performs device-seed signup
> or `#th=` fragment handoff. New web accounts are created via **email OTP** or
> **Google OAuth** (server sets `__Host-tentura_session`). Returning users recover
> with seed **inside WASM** at `/recover?invite=<code>#/recover-seed`; the seed
> never appears in a URL.

This document is kept for historical context when reading older commits or ADRs.

## What replaced it

| Flow | Mechanism |
|------|-----------|
| New user on invite page | Email OTP or Google → server resolve/create + accept invite + session cookie → `/invite/<code>?signed_in=1` |
| Returning user + seed | Landing links to `/recover?invite=<code>#/recover-seed` → seed entered in WASM → `#/accept-invite/<code>` |
| Existing user (cookie/session) | Landing CTA → `#/accept-invite/<code>` |

See [`invite-signup-landing-flow.md`](invite-signup-landing-flow.md) and
[`packages/landing/README.md`](../packages/landing/README.md).

## Former `#th=` transport (removed)

Previously, device-seed signup on the landing POSTed `accept-as-new`, then
redirected to `{origin}/#th=<base64url(json)>` with `{ userId, seed }`. WASM
captured the fragment before boot. That path failed when cookie-less visitors
hit `/` and Caddy served landing instead of WASM (ADR 0002).

Removed artifacts: `packages/landing/handoff.js`, `handoff-dev.html`,
`packages/client/.../web_handoff_*.dart`, `handoff_codec.dart`,
`scripts/check_handoff_contract.sh`, `#th=` capture in `packages/client/web/index.html`.
