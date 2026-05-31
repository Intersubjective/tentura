import { initAnalytics, track } from './analytics.js';
import { detectEnvironment, androidIntentUrl } from './webview.js';
import { parseInviteCode, fetchPreview } from './preview.js';
import { redirectToApp } from './handoff.js';
import { signUpWithSeed, webcryptoEd25519Available } from './auth.js';

// Absolute app origin (app.dev.tentura.io / app.tentura.io); see config.js.
const APP_BASE = (window.TENTURA || {}).appBase || 'https://app.dev.tentura.io/';

const app = document.getElementById('app');
const card = document.getElementById('card');
const env = detectEnvironment();

// Slice 3: device-seed signup is live. AUTH_ENABLED is the master kill-switch;
// even when on, signup is offered ONLY in Tier-1 system browsers with native
// WebCrypto Ed25519 — never in Tier-2 in-app webviews, where a device key would
// be lost when the webview closes (Tier-2 gets the recoverable email path in a
// later slice). `signupReady` is the resolved gate, computed in main().
const AUTH_ENABLED = true;
let signupReady = false;

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null) continue;
    if (k === 'class') node.className = v;
    else if (k.startsWith('on') && typeof v === 'function')
      node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null) continue;
    node.append(c.nodeType ? c : document.createTextNode(c));
  }
  return node;
}

const setState = (name) => {
  app.className = `state-${name}`;
};
const inviterName = (p) => p.inviter?.displayName?.trim() || 'Someone';

// Shared beacon context — shown above the CTA in EVERY state when present.
function beaconOverlay(p) {
  if (!p.beacon) return null;
  return el(
    'div',
    { class: 'beacon' },
    el('div', { class: 'beacon-label' }, `${inviterName(p)} shared`),
    el('div', { class: 'beacon-title' }, p.beacon.title || 'a beacon'),
    p.beacon.snippet
      ? el('div', { class: 'beacon-snippet' }, p.beacon.snippet)
      : null,
  );
}

function header(p) {
  const frag = document.createDocumentFragment();
  if (p.inviter?.image) {
    frag.append(el('img', { class: 'avatar', src: p.inviter.image, alt: '' }));
  }
  return frag;
}

// --- CTAs ------------------------------------------------------------------
function openAppUrl() {
  const code = parseInviteCode();
  return `${APP_BASE}?invite=${encodeURIComponent(code)}`;
}

function ctaOpenApp(label = 'Open Tentura') {
  return el(
    'a',
    { class: 'btn btn-primary', href: openAppUrl(), onclick: () => track('cta_open_app') },
    label,
  );
}

// Tier 2 escape. Android -> intent://; iOS -> copy link + coach to Safari
// (no clean programmatic iOS escape, Risk #2).
function ctaOpenInBrowser() {
  if (env.isAndroid) {
    return el(
      'a',
      {
        class: 'btn btn-primary',
        href: androidIntentUrl(location.href),
        onclick: () => track('cta_open_browser', { os: 'android' }),
      },
      'Open in your browser',
    );
  }
  return el(
    'button',
    {
      class: 'btn btn-primary',
      onclick: async () => {
        track('cta_open_browser', { os: 'ios' });
        try {
          await navigator.clipboard.writeText(location.href);
        } catch (_) {
          /* clipboard blocked in some webviews */
        }
        alert('Link copied. Open Safari and paste to continue.');
      },
    },
    'Copy link & open in Safari',
  );
}

// "I already have an account" — open the app (it holds/recreates the session,
// and consumes ?invite= to befriend in a later slice). The landing cannot sign
// in an existing account itself: it has no seed.
function ctaExisting() {
  return el(
    'a',
    { class: 'btn btn-secondary', href: openAppUrl(), onclick: () => track('cta_existing') },
    'I already have an account',
  );
}

// "I'm new — sign up" — reveal the inline device-seed signup form (Tier-1 only).
function ctaSignUp(p) {
  return el(
    'button',
    {
      class: 'btn btn-secondary',
      onclick: () => {
        track('cta_sign_up');
        showSignupForm(p);
      },
    },
    "I'm new — sign up",
  );
}

// Inline signup form: display name (required) + optional handle. On submit,
// generate the device key, consume the invite (accept-as-new), and hand off the
// resulting seed to the app.
function renderSignupForm(p) {
  const nameInput = el('input', {
    class: 'input',
    type: 'text',
    placeholder: 'Your name',
    maxlength: '50',
    autocomplete: 'name',
  });
  const handleInput = el('input', {
    class: 'input',
    type: 'text',
    placeholder: 'handle (optional)',
    maxlength: '30',
    autocapitalize: 'none',
    autocorrect: 'off',
    spellcheck: 'false',
  });
  const errorEl = el('p', { class: 'error' });
  const submit = el('button', { class: 'btn btn-primary' }, 'Create account');

  submit.addEventListener('click', async () => {
    errorEl.textContent = '';
    const displayName = nameInput.value.trim();
    if (!displayName) {
      errorEl.textContent = 'Please enter a display name.';
      return;
    }
    const label = submit.textContent;
    submit.disabled = true;
    submit.textContent = 'Signing up…';
    track('signup_start');
    try {
      const payload = await signUpWithSeed({
        code: parseInviteCode(),
        displayName,
        handle: handleInput.value,
      });
      track('signup_success');
      redirectToApp(payload); // leaves the page; the app boots authenticated
    } catch (e) {
      track('signup_error', { message: String(e), code: e.code });
      errorEl.textContent = e.message || 'Sign-up failed. Please try again.';
      submit.disabled = false;
      submit.textContent = label;
    }
  });

  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `Join ${inviterName(p)} on Tentura`),
    nameInput,
    handleInput,
    el(
      'p',
      { class: 'hint' },
      'Handle: 3–30 chars, lowercase letters, digits, underscore.',
    ),
    submit,
    errorEl,
    el('button', { class: 'btn btn-secondary', onclick: () => render(p) }, 'Back'),
  );
}

function showSignupForm(p) {
  card.replaceChildren();
  card.append(header(p));
  card.append(renderSignupForm(p));
}

// --- State renderers -------------------------------------------------------
function renderInvalid(p) {
  setState('invalid');
  const msg =
    p.codeStatus === 'consumed'
      ? 'This invite has already been used.'
      : p.codeStatus === 'expired'
        ? 'This invite has expired.'
        : 'We couldn’t find this invite.';
  return el(
    'div',
    { class: 'content' },
    el('h1', {}, 'This invite link is no longer valid'),
    el('p', {}, msg),
  );
}

function renderIsInviter(p) {
  setState('is-inviter');
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, 'This is your own invite'),
    el('p', {}, 'Share this link with someone you want to connect with.'),
    ctaOpenApp(),
  );
}

function renderAlreadyFriends(p) {
  setState('already-friends');
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `You’re already connected with ${inviterName(p)}`),
    ctaOpenApp(),
  );
}

function renderExistingUser(p) {
  setState('existing-user');
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `${inviterName(p)} wants to connect`),
    el('p', {}, 'Accept the invite in the app to become friends.'),
    ctaOpenApp('Open Tentura to accept'),
  );
}

function renderAnonymous(p) {
  setState('anonymous');
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `${inviterName(p)} invited you to Tentura`),
    el('p', {}, 'Tentura is invite-only. Three ways to continue:'),
    ctaOpenApp('Open the app'),
    ctaExisting(),
    signupReady
      ? ctaSignUp(p)
      : el(
          'p',
          { class: 'hint' },
          env.inApp
            ? 'To sign up, open this link in your browser.'
            : 'Sign-up needs an up-to-date browser.',
        ),
  );
}

function render(p) {
  card.replaceChildren();
  card.append(header(p));
  let content;
  switch (p.suggestedAction) {
    case 'self':
      content = renderIsInviter(p);
      break;
    case 'already-friends':
      content = renderAlreadyFriends(p);
      break;
    case 'accept-as-existing':
      content = renderExistingUser(p);
      break;
    case 'accept-as-new':
      content = renderAnonymous(p);
      break;
    case 'invalid':
    case 'consumed':
    case 'expired':
    default:
      content = renderInvalid(p);
      break;
  }
  card.append(content);
  // Tier 2 webviews: always surface the browser escape under the primary CTA.
  if (env.inApp && p.codeStatus === 'available') {
    card.append(ctaOpenInBrowser());
  }
}

function renderError() {
  setState('invalid');
  card.replaceChildren(
    el(
      'div',
      { class: 'content' },
      el('h1', {}, 'Something went wrong'),
      el('p', {}, 'Please try opening this link again.'),
    ),
  );
}

async function main() {
  initAnalytics();
  const code = parseInviteCode();
  // Funnel event fires BEFORE any WASM — the Phase 0 analytics deliverable.
  track('landing_view', { tier: env.tier, hasCode: Boolean(code) });
  if (!code) {
    renderError();
    return;
  }
  try {
    // Device-seed signup only in Tier-1 system browsers with native WebCrypto
    // Ed25519. Resolved alongside the preview so render() can branch on it.
    const [preview, wc] = await Promise.all([
      fetchPreview(code),
      env.inApp || !AUTH_ENABLED
        ? Promise.resolve(false)
        : webcryptoEd25519Available(),
    ]);
    signupReady = wc;
    track('preview_loaded', {
      codeStatus: preview.codeStatus,
      callerStatus: preview.callerStatus,
      hasBeacon: Boolean(preview.beacon),
    });
    render(preview);
  } catch (e) {
    track('preview_error', { message: String(e) });
    renderError();
  }
}

main();
