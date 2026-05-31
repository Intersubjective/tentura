// Device-seed signup (Tier-1 system browsers only) — see
// docs/invite-onboarding-auth-plan.md Phase 1 / slice 3.
//
// Generates an Ed25519 keypair with the *native* WebCrypto Ed25519 algorithm
// (no npm, no vendored lib), self-signs an "auth-request" JWT proving possession
// of the key, and POSTs it to the anonymous accept-as-new endpoint. The server
// creates the account + its `ed25519_device` credential, befriends the issuer,
// and forwards the beacon when present. On success we hand the *seed* (not the
// session token) to the WASM app via handoff.js; the app re-derives the keypair
// from the seed and signs in itself.
//
// Why Tier-1 only: a device key minted inside an in-app webview lives in that
// webview's ephemeral/siloed storage and is unrecoverable without a second
// credential — the user would lose the account when the webview closes. Tier-2
// webviews get the (recoverable) email path in a later slice; here they only see
// the "open in your browser" escape.
//
// Crypto contract (verified against the Dart client/server, see plan):
//   - The seed is the 32-byte RFC-8032 private seed = the trailing 32 bytes of
//     the PKCS#8 export of the WebCrypto private key. The app reconstructs the
//     same keypair via `newKeyFromSeed(base64Decode(seed))` (auth_box.dart).
//   - The seed string MUST be url-safe base64 *with* `=` padding: the app decodes
//     it with `base64Decode` (no normalize), which THROWS on un-padded input.
//   - The auth-request JWT segments use JWT-standard base64url *without* padding.
//   - The `pk` claim is url-safe base64 of the 32-byte public key (the server
//     normalizes it, so padding is tolerated); we emit it padded for parity with
//     the client's `base64UrlEncode`.
//   - No `exp` claim: the token is consumed server-side immediately, and
//     `dart_jsonwebtoken` only checks `exp` when present — omitting it avoids any
//     landing clock-skew failure.

const API_BASE = (window.TENTURA || {}).apiBase || ''; // '' = same origin

// Lowercased handle format mirrored from server user_handle_consts.dart.
export const HANDLE_RE = /^[a-z0-9_]{3,30}$/;

// --- base64url helpers -----------------------------------------------------
// Distinct from handoff.js's helper, which strips padding (correct for the
// fragment, fatal for the seed string — see contract above).
function bytesToBase64(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

// url-safe, WITH '=' padding (seed + pk).
function bytesToBase64urlPadded(bytes) {
  return bytesToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_');
}

// url-safe, WITHOUT padding (JWT segments).
function bytesToBase64urlNoPad(bytes) {
  return bytesToBase64urlPadded(bytes).replace(/=+$/, '');
}

function strToBase64urlNoPad(str) {
  return bytesToBase64urlNoPad(new TextEncoder().encode(str));
}

// --- feature detection -----------------------------------------------------
let _available;

// True iff the browser exposes native WebCrypto Ed25519 (generate + sign).
// Cached. Callers gate the signup CTA on this; older engines fall back to the
// "open in your browser" escape instead of a broken button.
export async function webcryptoEd25519Available() {
  if (_available !== undefined) return _available;
  try {
    const kp = await crypto.subtle.generateKey({ name: 'Ed25519' }, false, [
      'sign',
      'verify',
    ]);
    _available = Boolean(kp && kp.privateKey);
  } catch (_) {
    _available = false;
  }
  return _available;
}

// --- signup ----------------------------------------------------------------

// Error carrying the server's machine-readable code/message (from `e.toMap`) so
// the UI can show a field-level message (e.g. a taken/invalid handle) instead of
// a generic failure.
export class SignupError extends Error {
  constructor(message, { status, code } = {}) {
    super(message);
    this.name = 'SignupError';
    this.status = status;
    this.code = code;
  }
}

// Generate a device keypair, prove possession, consume the invite, and return
// the handoff payload `{ userId, seed, displayName }`. Throws SignupError on a
// server rejection (4xx) and a plain Error on transport failure.
export async function signUpWithSeed({ code, displayName, handle }) {
  if (!code) throw new SignupError('Missing invite code.');
  const name = (displayName || '').trim();
  if (!name) throw new SignupError('Please enter a display name.');
  const h = (handle || '').trim().toLowerCase();
  if (h && !HANDLE_RE.test(h)) {
    throw new SignupError(
      'Handle must be 3–30 characters: lowercase letters, digits, underscore.',
    );
  }

  const kp = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, [
    'sign',
    'verify',
  ]);
  // PKCS#8 export = DER prefix + the 32-byte seed; the seed is the trailing 32.
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey));
  const seedBytes = pkcs8.slice(pkcs8.length - 32);
  const pubBytes = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));

  const seed = bytesToBase64urlPadded(seedBytes); // padded — app's base64Decode needs it
  const pk = bytesToBase64urlPadded(pubBytes);

  // Self-signed EdDSA auth-request JWT. Only `pk` + a valid signature are
  // required by accept-as-new (it reads the invite code from the URL); `int` is
  // included for parity with the client, no `exp` (see contract).
  const signingInput =
    strToBase64urlNoPad(JSON.stringify({ alg: 'EdDSA', typ: 'JWT' })) +
    '.' +
    strToBase64urlNoPad(JSON.stringify({ int: 'sign_up', pk }));
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      { name: 'Ed25519' },
      kp.privateKey,
      new TextEncoder().encode(signingInput),
    ),
  );
  const authRequestToken = `${signingInput}.${bytesToBase64urlNoPad(sig)}`;

  const body = { authRequestToken, displayName: name };
  if (h) body.handle = h;

  let res;
  try {
    res = await fetch(
      `${API_BASE}/api/v2/invite/${encodeURIComponent(code)}/accept-as-new`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(body),
      },
    );
  } catch (e) {
    throw new Error(`signup request failed: ${e}`);
  }

  if (!res.ok) {
    // Controller returns 400 with jsonEncode(e.toMap) on domain errors.
    let code_;
    let message = `signup failed (${res.status})`;
    try {
      const err = await res.json();
      code_ = err.code ?? err.error;
      message = err.message ?? err.description ?? message;
    } catch (_) {
      /* non-JSON body */
    }
    throw new SignupError(message, { status: res.status, code: code_ });
  }

  // oauth2 map: { subject, expires_in, token_type, access_token }. We need only
  // `subject` (→ userId); the app re-signs-in from the seed, so access_token is
  // discarded here.
  const out = await res.json();
  return { userId: out.subject, seed, displayName: name };
}
