# ADR 0002: Cookie-presence routing at public root + client stale-session reconciliation

Status: Accepted (2026-06-06)

## Context

Tentura serves a static invite **landing surface** and a Flutter **WASM surface** on one public origin (`tentura.io`, `dev.tentura.io`, local HTTPS). Signed-out users opening `/` must see the invite-only landing, not boot WASM. Signed-in users opening `/` must boot the product.

HttpOnly **browser sessions** use `__Host-tentura_session`. Caddy cannot validate session tokens at the edge without forward-auth infrastructure. Cookie *presence* is a cheap first-byte signal; the client/server bootstrap validates the token.

Stale, revoked, or fake cookies still match presence routing and would otherwise loop: WASM boots → session rejected → navigate to `/` → WASM again.

## Decision

1. **Caddy Level 1 at `/` only:** If `__Host-tentura_session` is present on `GET /`, serve WASM (`APP_ROOT`) with COOP/COEP. Otherwise serve landing (`LANDING_ROOT`) without COOP/COEP. `/invite/*` remains static regardless of cookie. Deep app routes remain WASM.

2. **Root HTML is not cacheable without cookie awareness:** Both root branches emit `Vary: Cookie` and `Cache-Control: no-store`.

3. **Client stale-session reconciliation:** On server rejection (401/403 from session bootstrap), POST logout to clear the cookie, clean ghost session-only local identity, then navigate. Reload `/` only after an acknowledged logout response **and** at most once per tab (one-shot `sessionStorage` guard). If clear fails or the guard is already set, fall back to `/invite/` (cookie-independent static path).

4. **Local dev:** Root split is opt-in via `LOCAL_ROOT_SPLIT=on` so `flutter run` at `/` is unchanged by default.

5. **Service worker:** App preload worker bypasses `/invite/`; it must not intercept `/` or landing assets.

## Consequences

- Stale cookies pay one extra WASM load before landing; acceptable vs forward-auth complexity.
- Sign-out clears browser cookies after remote sign-out (preserving bearer for `GSignOutReq`), then navigates to `/` or `/invite/`.
- ADR does not replace Level 2 forward-auth if cookie-presence routing proves insufficient.

## Alternatives considered

- **`/welcome` static path + client redirect** — simpler Caddy, but `/` would not match the “Instagram-like root = product when signed in” contract without extra redirects.
- **Level 2 forward-auth** — correct stale cookies at the edge; deferred for infra cost.
- **Move WASM to `/app/*`** — large URL/topology change; rejected for this slice.
