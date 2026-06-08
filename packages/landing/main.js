import { initAnalytics, track } from './analytics.js';
import { detectEnvironment, androidIntentUrl } from './webview.js';
import { parseInviteCode, fetchPreview } from './preview.js';
import { redirectToApp } from './handoff.js';
import {
  signUpWithSeed,
  startEmailMagicLink,
  webcryptoEd25519Available,
} from './auth.js';
import { resolveAppBase } from './resolve_app_base.js';
import { parseInviteEntryInput, invitePathForCode } from './invite_entry.js';

const GOOGLE_ENABLED = Boolean((window.TENTURA || {}).googleEnabled);
const API_BASE = (window.TENTURA || {}).apiBase || '';

let APP_BASE = '';

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

function setPageTitle(title) {
  document.title = title;
}

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
function appHashUrl(path) {
  const base = APP_BASE.replace(/\/$/, '');
  const normalized = path.startsWith('/') ? path : `/${path}`;
  return `${base}#${normalized}`;
}

function openProductUrl() {
  return APP_BASE.endsWith('/') ? APP_BASE : `${APP_BASE}/`;
}

function openAcceptInviteUrl(code) {
  return appHashUrl(`/accept-invite/${encodeURIComponent(code)}`);
}

function ctaOpenApp(label = 'Open Tentura') {
  return el(
    'a',
    {
      class: 'btn btn-primary',
      href: openProductUrl(),
      onclick: () => track('cta_open_app'),
    },
    label,
  );
}

function ctaOpenAcceptInvite(label = 'Open Tentura to accept') {
  const code = parseInviteCode();
  return el(
    'a',
    {
      class: 'btn btn-primary',
      href: openAcceptInviteUrl(code),
      onclick: () => track('cta_open_accept_invite'),
    },
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
      type: 'button',
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

// "I already have an account" — focus email sign-in on the landing.
function ctaExisting() {
  return el(
    'button',
    {
      class: 'btn btn-secondary',
      type: 'button',
      onclick: () => {
        track('cta_existing');
        document.querySelector('.email-auth input')?.focus();
      },
    },
    'I already have an account',
  );
}

function googleReturnTo(inviteCode) {
  if (!inviteCode) return null;
  const origin = API_BASE
    ? new URL(API_BASE, window.location.href).origin
    : window.location.origin;
  return `${origin}/invite/${encodeURIComponent(inviteCode)}`;
}

function ctaGoogleSignIn(inviteCode) {
  if (!GOOGLE_ENABLED || env.inApp) return null;
  const origin = API_BASE
    ? new URL(API_BASE, window.location.href).origin
    : window.location.origin;
  const url = new URL('/api/auth/google/start', origin);
  if (inviteCode) {
    url.searchParams.set('invite', inviteCode);
    const returnTo = googleReturnTo(inviteCode);
    if (returnTo) url.searchParams.set('returnTo', returnTo);
  }
  return el(
    'a',
    {
      class: 'btn btn-secondary',
      href: url.toString(),
      onclick: () => track('cta_google_sign_in', { hasInvite: Boolean(inviteCode) }),
    },
    'Continue with Google',
  );
}

// "I'm new — sign up" — reveal the inline device-seed signup form (Tier-1 only).
function ctaSignUp(p) {
  return el(
    'button',
    {
      class: 'btn btn-secondary',
      type: 'button',
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
  setPageTitle(`Join ${inviterName(p)} on Tentura`);
  const nameInput = el('input', {
    class: 'input',
    type: 'text',
    id: 'signup-name',
    name: 'displayName',
    placeholder: 'Your name',
    maxlength: '50',
    autocomplete: 'section-signup name',
  });
  const handleInput = el('input', {
    class: 'input',
    type: 'text',
    id: 'signup-handle',
    name: 'handle',
    placeholder: 'handle (optional)',
    maxlength: '30',
    autocomplete: 'section-signup off',
    autocapitalize: 'none',
    autocorrect: 'off',
    spellcheck: 'false',
  });
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const submit = el('button', { class: 'btn btn-primary', type: 'submit' }, 'Create account');

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    const displayName = nameInput.value.trim();
    if (!displayName) {
      errorEl.textContent = 'Please enter a display name.';
      nameInput.focus();
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
    } catch (err) {
      track('signup_error', { message: String(err), code: err.code });
      errorEl.textContent = err.message || 'Sign-up failed. Please try again.';
      submit.disabled = false;
      submit.textContent = label;
    }
  };

  return el(
    'form',
    {
      class: 'content signup-form',
      onsubmit: onSubmit,
      autocomplete: 'on',
    },
    beaconOverlay(p),
    el('h1', {}, `Join ${inviterName(p)} on Tentura`),
    el('label', { class: 'field-label', for: 'signup-name' }, 'Display name'),
    nameInput,
    el('label', { class: 'field-label', for: 'signup-handle' }, 'Handle (optional)'),
    handleInput,
    el(
      'p',
      { class: 'hint' },
      'Handle: 3–30 chars, lowercase letters, digits, underscore.',
    ),
    submit,
    errorEl,
    el(
      'button',
      { class: 'btn btn-secondary', type: 'button', onclick: () => render(p) },
      'Back',
    ),
  );
}

function showSignupForm(p) {
  card.replaceChildren();
  card.append(header(p));
  card.append(renderSignupForm(p));
}

function renderEmailMagicLinkForm() {
  const emailInput = el('input', {
    class: 'input',
    type: 'email',
    id: 'email-signin',
    // Avoid `name="email"` — paired with any text field on the page, Firefox
    // treats the form as username+password and offers saved site secrets.
    name: 'identifier',
    placeholder: 'your@email.com',
    autocomplete: 'section-signin email',
    inputmode: 'email',
  });
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const successEl = el('p', { class: 'hint' });
  const submit = el(
    'button',
    { class: 'btn btn-secondary', type: 'submit' },
    'Email me a sign-in link',
  );

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    successEl.textContent = '';
    const label = submit.textContent;
    submit.disabled = true;
    submit.textContent = 'Sending…';
    track('email_link_start');
    try {
      await startEmailMagicLink({
        email: emailInput.value,
        code: parseInviteCode(),
      });
      track('email_link_sent');
      successEl.textContent =
        'If that address can sign in, we sent a link. Open it in your browser (not this in-app viewer).';
      submit.textContent = 'Link sent';
    } catch (err) {
      track('email_link_error', { message: String(err) });
      errorEl.textContent = err.message || 'Could not send link. Try again.';
      submit.disabled = false;
      submit.textContent = label;
    }
  };

  return el(
    'form',
    {
      class: 'email-auth',
      onsubmit: onSubmit,
      autocomplete: 'on',
      'data-lpignore': 'true',
    },
    el('label', { class: 'field-label', for: 'email-signin' }, 'Email'),
    emailInput,
    submit,
    errorEl,
    successEl,
    el(
      'p',
      { class: 'hint' },
      'We never confirm whether an account exists for this address.',
    ),
  );
}

function renderInviteEntryForm() {
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const input = el('input', {
    class: 'input',
    type: 'text',
    id: 'invite-entry',
    name: 'invite-code',
    placeholder: 'Iabc123 or https://…/invite/Iabc123',
    autocomplete: 'section-invite off',
    autocapitalize: 'none',
    spellcheck: 'false',
    'data-lpignore': 'true',
  });

  const onSubmit = (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    const result = parseInviteEntryInput(input.value);
    if (!result.ok) {
      errorEl.textContent = result.error;
      input.focus();
      return;
    }
    track('cta_invite_entry', { method: 'manual' });
    location.assign(invitePathForCode(result.code));
  };

  return el(
    'form',
    {
      class: 'invite-entry',
      onsubmit: onSubmit,
      autocomplete: 'off',
      'data-lpignore': 'true',
    },
    el('label', { class: 'field-label', for: 'invite-entry' }, 'Invite link or code'),
    input,
    el(
      'button',
      { type: 'submit', class: 'btn btn-primary' },
      'Continue with invite',
    ),
    errorEl,
    el(
      'p',
      { class: 'hint' },
      'New here? Paste the invite link a friend sent you.',
    ),
  );
}

function isSignedInReturn() {
  return new URLSearchParams(location.search).get('signed_in') === '1';
}

function signedInFlash() {
  if (!isSignedInReturn()) return null;
  return el(
    'p',
    { class: 'hint' },
    'You are signed in. Open Tentura below to continue.',
  );
}

// --- State renderers -------------------------------------------------------
function renderInvalid(p) {
  setState('invalid');
  setPageTitle('Invite link invalid — Tentura');
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
  setPageTitle('Your invite — Tentura');
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
  const name = inviterName(p);
  if (isSignedInReturn()) {
    setPageTitle('You’re all set — Tentura');
    return el(
      'div',
      { class: 'content' },
      beaconOverlay(p),
      el('h1', {}, 'You’re all set'),
      el(
        'p',
        {},
        `Your account is ready, and ${name} is connected with you. Open Tentura to continue.`,
      ),
      ctaOpenApp(),
    );
  }
  setPageTitle(`Connected with ${name} — Tentura`);
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `You’re connected with ${name}`),
    el('p', {}, 'Open Tentura to continue.'),
    ctaOpenApp(),
  );
}

function renderExistingUser(p) {
  setState('existing-user');
  setPageTitle(`${inviterName(p)} invited you — Tentura`);
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, `${inviterName(p)} wants to connect`),
    el('p', {}, 'Accept the invite in the app to become friends.'),
    ctaOpenAcceptInvite('Open Tentura to accept'),
  );
}

function renderAnonymous(p) {
  setState('anonymous');
  setPageTitle(`${inviterName(p)} invited you — Tentura`);
  const code = parseInviteCode();
  const children = [
    beaconOverlay(p),
    signedInFlash(),
    el('h1', {}, `${inviterName(p)} invited you to Tentura`),
    el(
      'p',
      {},
      env.inApp
        ? 'Open this link in your browser, or use email to get a sign-in link.'
        : 'Tentura is invite-only. Sign in with email or Google, or create an account below.',
    ),
    renderEmailMagicLinkForm(),
    ctaGoogleSignIn(code),
    ctaExisting(),
  ];
  if (!env.inApp && signupReady) {
    children.push(ctaSignUp(p));
  } else if (!env.inApp) {
    children.push(
      el('p', { class: 'hint' }, 'Sign-up needs an up-to-date browser.'),
    );
  }
  return el('div', { class: 'content' }, ...children);
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
  setPageTitle('Something went wrong — Tentura');
  card.replaceChildren(
    el(
      'div',
      { class: 'content' },
      el('h1', {}, 'Something went wrong'),
      el('p', {}, 'Please try opening this link again.'),
    ),
  );
}

// Landing visited with no `/invite/:code` — e.g. the WASM app bounced a
// logged-out / unauthenticated web user here (the app has no login UI). Tentura
// is invite-only, so there is no public signup; show a neutral message rather
// than the link-specific "Something went wrong" error.
function renderConfigError(message) {
  setState('invalid');
  setPageTitle('Configuration error — Tentura');
  card.replaceChildren(
    el(
      'div',
      { class: 'content' },
      el('h1', {}, 'Configuration error'),
      el('p', {}, message),
      el(
        'p',
        {},
        'Local dev: copy .env.example to .env, then run ./scripts/sync-landing-local-config.sh',
      ),
    ),
  );
}

function renderNoInvite() {
  setState('no-invite');
  setPageTitle('Tentura — invite-only');

  const signInBlock = el('div', {
    class: 'signin-options',
    id: 'signin-options',
    role: 'region',
    'aria-label': 'Sign in',
    hidden: 'hidden',
  });

  const mountSignInOptions = () => {
    if (signInBlock.querySelector('.email-auth')) return;
    const signInItems = [
      el('p', { class: 'section-label' }, 'Sign in'),
      renderEmailMagicLinkForm(),
    ];
    if (!env.inApp) {
      const google = ctaGoogleSignIn('');
      if (google) signInItems.push(google);
    } else {
      signInItems.push(ctaOpenInBrowser());
    }
    signInBlock.replaceChildren(...signInItems);
  };

  const existingToggle = el(
    'button',
    {
      class: 'btn btn-secondary',
      type: 'button',
      'aria-expanded': 'false',
      'aria-controls': 'signin-options',
      onclick: () => {
        track('cta_existing');
        mountSignInOptions();
        signInBlock.hidden = false;
        existingToggle.setAttribute('aria-expanded', 'true');
        existingToggle.hidden = true;
        signInBlock.querySelector('input')?.focus();
      },
    },
    'I already have an account',
  );

  card.replaceChildren(
    el(
      'div',
      { class: 'content' },
      el('p', { class: 'eyebrow' }, 'Private coordination network'),
      el('h1', {}, 'Tentura is invite-only'),
      el('p', {}, 'Join with a personal invite from someone you know.'),
      signedInFlash(),
      renderInviteEntryForm(),
      existingToggle,
      signInBlock,
    ),
  );
}

function addAppPreconnect(appBase) {
  try {
    const origin = new URL(appBase).origin;
    if (document.querySelector(`link[rel="preconnect"][href="${origin}"]`)) {
      return;
    }
    const link = document.createElement('link');
    link.rel = 'preconnect';
    link.href = origin;
    document.head.appendChild(link);
  } catch (_) {
    /* invalid appBase */
  }
}

async function main() {
  try {
    APP_BASE = resolveAppBase();
    addAppPreconnect(APP_BASE);
  } catch (e) {
    renderConfigError(String(e.message || e));
    return;
  }
  initAnalytics();
  const code = parseInviteCode();
  // Funnel event fires BEFORE any WASM — the Phase 0 analytics deliverable.
  track('landing_view', { tier: env.tier, hasCode: Boolean(code) });
  if (!code) {
    renderNoInvite();
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
