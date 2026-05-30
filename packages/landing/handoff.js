// Landing -> app session handoff (see docs/handoff-contract.md).
//
// Hands the freshly-authenticated account (seed + id) to the WASM app on the
// sibling app subdomain via a URL *fragment*. The app captures it before boot,
// writes it to its own secure storage, then scrubs it. No secret reaches the
// server — fragments are never sent in the HTTP request, so they stay out of
// Caddy/Hasura access logs.
//
// The CTAs that *produce* a payload and call redirectToApp() are wired with
// real auth in a later slice; this module is the transport only.

// HANDOFF-CONTRACT-PIN (keep in sync with
// packages/client/lib/features/auth/data/service/web_handoff_web.dart and
// docs/handoff-contract.md — enforced by scripts/check_handoff_contract.sh):
//   key=th v userId seed displayName
const HANDOFF_KEY = 'th';
const HANDOFF_VERSION = 1;

// Absolute app origin (app.dev.tentura.io / app.tentura.io); see config.js.
const APP_BASE = (window.TENTURA || {}).appBase || 'https://app.dev.tentura.io/';

// UTF-8-safe base64url. Bare btoa() throws on non-ASCII (Cyrillic/accented
// display names); encode to UTF-8 bytes first, then make it URL-safe.
function base64url(str) {
  const b64 = btoa(unescape(encodeURIComponent(str)));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function buildHandoffUrl(appBase, { userId, seed, displayName }) {
  const payload = { v: HANDOFF_VERSION, userId, seed };
  if (displayName) payload.displayName = displayName;
  const encoded = base64url(JSON.stringify(payload));
  const base = appBase.endsWith('/') ? appBase : `${appBase}/`;
  return `${base}#${HANDOFF_KEY}=${encoded}`;
}

export function redirectToApp(payload, appBase = APP_BASE) {
  location.assign(buildHandoffUrl(appBase, payload));
}
