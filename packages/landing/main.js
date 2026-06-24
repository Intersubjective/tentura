import { initAnalytics, initVisit, track, trackError, setAttemptId, setAccount, newAttemptId } from './analytics.js';
import { detectEnvironment, androidIntentUrl } from './webview.js';
import { parseInviteCode, fetchPreview } from './preview.js';
import { startEmailMagicLink } from './auth.js';
import { parseInviteEntryInput, invitePathForCode } from './invite_entry.js';
import { startAppPreload } from './app_preload.js';
import {
  isNewSignupReturn,
  isOnboardingDone,
  fetchMyProfile,
  renderPostSignup,
} from './onboarding.js';

const GOOGLE_ENABLED = Boolean((window.TENTURA || {}).googleEnabled);
const API_BASE = (window.TENTURA || {}).apiBase || '';

const app = document.getElementById('app');
const card = document.getElementById('card');
const env = detectEnvironment();

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
  const normalized = path.startsWith('/') ? path : `/${path}`;
  return `${location.origin}/#${normalized}`;
}

function openProductUrl() {
  return `${location.origin}/`;
}

function openAcceptInviteUrl(code) {
  return appHashUrl(`/accept-invite/${encodeURIComponent(code)}`);
}

function appRecoverUrl(inviteCode) {
  const attemptId = newAttemptId('seed');
  const url = new URL('/recover', location.origin);
  url.hash = '/recover-seed';
  url.searchParams.set('auth_attempt_id', attemptId);
  if (inviteCode) {
    url.searchParams.set('invite', inviteCode);
  }
  return { href: url.toString(), attemptId };
}

function ctaRecoverSeed(inviteCode) {
  const { href, attemptId } = appRecoverUrl(inviteCode);
  return el(
    'a',
    {
      class: 'btn btn-secondary',
      href,
      onclick: () => {
        setAttemptId(attemptId, 'seed');
        track('seed_recovery_clicked');
      },
    },
    'Recover from seed',
  );
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
  const attemptId = newAttemptId('google');
  const url = new URL('/api/auth/google/start', origin);
  url.searchParams.set('auth_attempt_id', attemptId);
  if (inviteCode) {
    url.searchParams.set('invite', inviteCode);
    const returnTo = googleReturnTo(inviteCode);
    if (returnTo) {
      const returnUrl = new URL(returnTo);
      returnUrl.searchParams.set('auth_attempt_id', attemptId);
      url.searchParams.set('returnTo', returnUrl.toString());
    }
  }
  return el(
    'a',
    {
      class: 'btn btn-secondary',
      href: url.toString(),
      onclick: () => {
        setAttemptId(attemptId, 'google');
        track('google_start_clicked', { hasInvite: Boolean(inviteCode) });
      },
    },
    'Continue with Google',
  );
}

function buildSignInOptionItems(inviteCode) {
  const items = [
    el('p', { class: 'section-label' }, 'Sign in'),
    renderEmailMagicLinkForm(),
  ];
  if (env.inApp) {
    items.push(ctaOpenInBrowser());
  } else {
    const google = ctaGoogleSignIn(inviteCode);
    if (google) items.push(google);
    items.push(ctaRecoverSeed(inviteCode));
  }
  return items;
}

function createSignInReveal(inviteCode, { blockId = 'signin-options', hideOnReveal = [] } = {}) {
  const signInBlock = el('div', {
    class: 'signin-options',
    id: blockId,
    role: 'region',
    'aria-label': 'Sign in',
    hidden: 'hidden',
  });

  const inviteModeUndo = el(
    'button',
    {
      class: 'hint hint-link',
      type: 'button',
      hidden: 'hidden',
    },
    'Have an invite link?',
  );

  inviteModeUndo.addEventListener('click', () => {
    track('cta_invite_mode');
    signInBlock.hidden = true;
    inviteModeUndo.hidden = true;
    existingToggle.hidden = false;
    existingToggle.setAttribute('aria-expanded', 'false');
    for (const node of hideOnReveal) node.hidden = false;
  });

  const existingToggle = el(
    'button',
    {
      class: 'btn btn-secondary',
      type: 'button',
      'aria-expanded': 'false',
      'aria-controls': blockId,
    },
    'I already have an account',
  );

  existingToggle.addEventListener('click', () => {
    track('cta_existing');
    if (!signInBlock.querySelector('.email-auth')) {
      signInBlock.replaceChildren(...buildSignInOptionItems(inviteCode), inviteModeUndo);
    }
    signInBlock.hidden = false;
    inviteModeUndo.hidden = false;
    existingToggle.setAttribute('aria-expanded', 'true');
    existingToggle.hidden = true;
    for (const node of hideOnReveal) node.hidden = true;
    signInBlock.querySelector('input')?.focus();
  });

  return { existingToggle, signInBlock };
}

// Email, Google, and seed recovery for invite pages.
function renderInviteAuthOptions(inviteCode) {
  const items = [
    el('p', { class: 'section-label' }, 'Get started'),
    renderEmailMagicLinkForm(),
  ];
  if (env.inApp) {
    items.push(ctaOpenInBrowser());
  } else {
    const google = ctaGoogleSignIn(inviteCode);
    if (google) items.push(google);
    items.push(ctaRecoverSeed(inviteCode));
  }
  return items;
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
    track('email_start_clicked');
    try {
      const attemptId = await startEmailMagicLink({
        email: emailInput.value,
        code: parseInviteCode(),
      });
      if (attemptId) setAttemptId(attemptId, 'email');
      track('email_start_accepted');
      successEl.textContent =
        'If that address can sign in, we sent a link. Open it in your browser (not this in-app viewer).';
      submit.textContent = 'Link sent';
    } catch (err) {
      trackError('email_start_error', err);
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
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    signedInFlash(),
    el('h1', {}, `${inviterName(p)} invited you to Tentura`),
    el(
      'p',
      {},
      env.inApp
        ? 'Open this link in your browser, or create an account with email.'
        : 'Create an account with email or Google, or sign in with seed recovery if you already have one.',
    ),
    ...renderInviteAuthOptions(code),
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
function renderNoInvite() {
  setState('no-invite');
  setPageTitle('Tentura — invite-only');

  const inviteIntro = el('p', {}, 'Join with a personal invite from someone you know.');
  const inviteForm = renderInviteEntryForm();
  const { existingToggle, signInBlock } = createSignInReveal('', {
    hideOnReveal: [inviteIntro, inviteForm],
  });

  const children = [
    el('p', { class: 'eyebrow' }, 'Private coordination network'),
    el('h1', {}, 'Tentura is invite-only'),
    inviteIntro,
    signedInFlash(),
    inviteForm,
    existingToggle,
    signInBlock,
  ];
  if (isSignedInReturn()) {
    children.push(ctaOpenApp());
  }

  card.replaceChildren(el('div', { class: 'content' }, ...children));
}

function applyGoogleReturnAttemptId() {
  const id = new URLSearchParams(location.search).get('auth_attempt_id');
  if (id) setAttemptId(id, 'google');
}

async function main() {
  try {
    initAnalytics();
    const code = parseInviteCode();
    initVisit({ env, hasCode: Boolean(code) });
    startAppPreload({ env, track });
    track('landing_view', { tier: env.tier, hasCode: Boolean(code) });

    if (isSignedInReturn()) {
      applyGoogleReturnAttemptId();
    }

    if (isNewSignupReturn(location.search) && !isOnboardingDone(sessionStorage)) {
      const profile = await fetchMyProfile();
      if (profile) {
        setAccount(profile.id);
        track('post_signup_view', { hasCode: Boolean(code) });
        renderPostSignup({
          card,
          profile,
          setState,
          setPageTitle,
          track,
          openProductUrl,
          storage: sessionStorage,
        });
        return;
      }
      track('post_signup_fallback');
    }

    if (!code) {
      renderNoInvite();
      return;
    }
    try {
      const preview = await fetchPreview(code);
      track('preview_loaded', {
        codeStatus: preview.codeStatus,
        callerStatus: preview.callerStatus,
        hasBeacon: Boolean(preview.beacon),
      });
      render(preview);
    } catch (e) {
      trackError('preview_error', e);
      renderError();
    }
  } catch (e) {
    const Sentry = window.Sentry;
    if (Sentry) Sentry.captureException(e);
    trackError('landing_boot_error', e);
    renderError();
  }
}

main();
