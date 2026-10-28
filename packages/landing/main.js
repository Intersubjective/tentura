import { initAnalytics, initVisit, track, trackError, setAttemptId, setAccount, newAttemptId } from './analytics.js';
import { detectEnvironment, androidIntentUrl } from './webview.js';
import { parseInviteCode, parseInviteCodeRaw, fetchPreview } from './preview.js';
import { startEmailMagicLink, startTestLogin } from './auth.js';
import {
  parseInviteEntryInput,
  invitePathForCode,
  inviteCodeHadTrailingDash,
  INVITE_CODE_PATTERN,
} from './invite_entry.js';
import { startAppPreload } from './app_preload.js';
import { installBfcacheRefresh } from './bfcache.js';
import {
  isNewSignupReturn,
  isOnboardingDone,
  fetchMyProfile,
  renderPostSignup,
  shouldRunPostSignup,
  inviteLandingCopy,
  RECOVER_SEED_LINK_LABEL,
  authErrorMessage,
  urlWithoutAuthError,
  inviterDisplayName,
  initLocale,
  t,
} from './onboarding.js';
import { needsExpand, beaconBodyText } from './beacon_overlay.js';

const LANDING_CONFIG = window.TENTURA || {};
const GOOGLE_ENABLED = Boolean(
  LANDING_CONFIG.googleEnabled && !LANDING_CONFIG.emailOnlyQa,
);
const QA_TEST_LOGIN = Boolean(LANDING_CONFIG.qaTestLogin);
const API_BASE = (window.TENTURA || {}).apiBase || '';

// #663: pick the reader's language (and set <html lang>) before any render.
initLocale();

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

const inviterName = (p) => inviterDisplayName(p.inviter?.displayName);

// Shared beacon context — shown above the CTA in EVERY state when present.
function beaconOverlay(p) {
  if (!p.beacon) return null;

  const bodyId = 'beacon-body';
  const canExpand = needsExpand(p.beacon.snippet, p.beacon.description);
  const initialBody = beaconBodyText(p.beacon, false);

  const body = el(
    'div',
    {
      class: 'beacon-snippet',
      id: bodyId,
    },
    initialBody,
  );

  const children = [
    el('div', { class: 'beacon-label' }, t('{name} shared', { name: inviterName(p) })),
    el(
      'div',
      { class: 'beacon-title' },
      p.beacon.title || (p.beacon.kind === 'post' ? t('a post') : t('a request')),
    ),
  ];
  if (initialBody) children.push(body);

  if (canExpand) {
    let expanded = false;
    const toggle = el(
      'button',
      {
        class: 'beacon-expand',
        type: 'button',
        'aria-expanded': 'false',
        'aria-controls': bodyId,
      },
      t('Show more'),
    );
    toggle.addEventListener('click', () => {
      expanded = !expanded;
      body.textContent = beaconBodyText(p.beacon, expanded);
      body.classList.toggle('is-expanded', expanded);
      toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
      toggle.textContent = expanded ? t('Show less') : t('Show more');
      track('beacon_snippet_toggled', { expanded });
    });
    children.push(toggle);
  }

  return el('div', { class: 'beacon' }, ...children);
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
      // A rare recovery path: a text link, not a second full-weight button
      // under "Email me a sign-in link".
      class: 'hint-link',
      href,
      onclick: () => {
        setAttemptId(attemptId, 'seed');
        track('seed_recovery_clicked');
      },
    },
    t(RECOVER_SEED_LINK_LABEL),
  );
}

function ctaOpenApp(label = t('Continue to Tentura')) {
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

function ctaOpenAcceptInvite(label = t('Open Tentura to accept')) {
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
      t('Open in your browser'),
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
        alert(t('Link copied. Open Safari and paste to continue.'));
      },
    },
    t('Copy link & open in Safari'),
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
    t('Continue with Google'),
  );
}

function buildSignInOptionItems(inviteCode) {
  const items = [
    el('p', { class: 'section-label' }, t('Sign in')),
    renderEmailMagicLinkForm(),
  ];
  if (QA_TEST_LOGIN) {
    items.push(renderQaTestLoginForm(inviteCode));
  }
  if (env.inApp) {
    items.push(ctaOpenInBrowser());
  } else {
    const google = ctaGoogleSignIn(inviteCode);
    if (google) items.push(google);
    items.push(ctaRecoverSeed(inviteCode));
  }
  return items;
}

function createSignInReveal(inviteCode, {
  blockId = 'signin-options',
  hideOnReveal = [],
  expandedByDefault = false,
  onSignInModeChange = null,
} = {}) {
  const signInBlock = el('div', {
    class: 'signin-options',
    id: blockId,
    role: 'region',
    'aria-label': t('Sign in'),
    hidden: expandedByDefault ? null : 'hidden',
  });

  const inviteModeUndo = el(
    'button',
    {
      class: 'hint hint-link',
      type: 'button',
      hidden: 'hidden',
    },
    t('Have an invite link?'),
  );

  inviteModeUndo.addEventListener('click', () => {
    track('cta_invite_mode');
    signInBlock.hidden = true;
    inviteModeUndo.hidden = true;
    existingToggle.hidden = false;
    existingToggle.setAttribute('aria-expanded', 'false');
    for (const node of hideOnReveal) node.hidden = false;
    onSignInModeChange?.(false);
  });

  const existingToggle = el(
    'button',
    {
      class: 'btn btn-secondary',
      type: 'button',
      'aria-expanded': 'false',
      'aria-controls': blockId,
    },
    t('I already have an account'),
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
    onSignInModeChange?.(true);
  });

  if (expandedByDefault) {
    signInBlock.replaceChildren(...buildSignInOptionItems(inviteCode));
    existingToggle.hidden = true;
    existingToggle.setAttribute('aria-expanded', 'true');
    onSignInModeChange?.(true);
  }

  return { existingToggle, signInBlock };
}

// Email and Google sign-in for invite pages; the seed link sits behind the
// existing-account toggle (createSignInReveal).
function renderInviteAuthOptions(inviteCode) {
  const items = [
    el('p', { class: 'section-label' }, t('Get started')),
    renderEmailMagicLinkForm(),
  ];
  if (QA_TEST_LOGIN) {
    items.push(renderQaTestLoginForm(inviteCode));
  }
  if (env.inApp) {
    items.push(ctaOpenInBrowser());
  } else {
    const google = ctaGoogleSignIn(inviteCode);
    if (google) items.push(google);
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
  const errorEl = el('p', { class: 'error', role: 'alert', id: 'email-signin-error' });
  const successEl = el('div', {
    class: 'email-success',
    role: 'status',
    hidden: 'hidden',
  });
  const submit = el(
    'button',
    { class: 'btn btn-secondary', type: 'submit' },
    t('Email me a sign-in link'),
  );

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    emailInput.removeAttribute('aria-invalid');
    emailInput.removeAttribute('aria-describedby');
    successEl.replaceChildren();
    successEl.hidden = true;
    const label = submit.textContent;
    submit.disabled = true;
    submit.textContent = t('Sending…');
    track('email_start_clicked');
    try {
      const attemptId = await startEmailMagicLink({
        email: emailInput.value,
        code: parseInviteCode(),
      });
      if (attemptId) setAttemptId(attemptId, 'email');
      track('email_start_accepted');
      successEl.replaceChildren(
        el('p', { class: 'email-success-title' }, t('Check your email')),
        el(
          'p',
          { class: 'email-success-body' },
          t(
            'If that address can sign in, we sent a link. Open the message and tap the link to continue.',
          ),
        ),
        el(
          'button',
          { class: 'btn btn-secondary', type: 'button', onclick: useDifferentAddress },
          t('Use a different address'),
        ),
      );
      successEl.hidden = false;
      emailInput.disabled = true;
      submit.disabled = true;
      submit.textContent = t('Link sent — check your email');
      successEl.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    } catch (err) {
      trackError('email_start_error', err);
      errorEl.textContent = err.message || t('Could not send link. Try again.');
      submit.disabled = false;
      submit.textContent = label;
      if (err?.userInput) {
        emailInput.setAttribute('aria-invalid', 'true');
        emailInput.setAttribute('aria-describedby', errorEl.id);
        emailInput.focus();
      }
    }
  };

  // After a real send the field is locked; a typo that passed the format
  // check (me@gmial.com) must not require a page reload (#385).
  const useDifferentAddress = () => {
    successEl.replaceChildren();
    successEl.hidden = true;
    emailInput.disabled = false;
    submit.disabled = false;
    submit.textContent = t('Email me a sign-in link');
    emailInput.focus();
    emailInput.select();
  };

  return el(
    'form',
    {
      class: 'email-auth',
      onsubmit: onSubmit,
      autocomplete: 'on',
      novalidate: '',
      'data-lpignore': 'true',
    },
    el('label', { class: 'field-label', for: 'email-signin' }, t('Email')),
    el(
      'p',
      { class: 'field-hint' },
      t('We never confirm whether an account exists for this address.'),
    ),
    emailInput,
    submit,
    errorEl,
    successEl,
  );
}

function renderQaTestLoginForm(inviteCode) {
  const emailInput = el('input', {
    class: 'input',
    type: 'email',
    id: 'email-qa-test-login',
    name: 'qa-test-login-identifier',
    placeholder: 'user@test.tentura.local',
    autocomplete: 'section-qa-test-login email',
    inputmode: 'email',
  });
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const submit = el(
    'button',
    { class: 'btn btn-secondary', type: 'submit' },
    t('Test login'),
  );

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    const label = submit.textContent;
    submit.disabled = true;
    submit.textContent = t('Signing in…');
    track('qa_test_login_clicked');
    try {
      const { redirectUrl } = await startTestLogin({
        email: emailInput.value,
        code: inviteCode ?? parseInviteCode(),
      });
      track('qa_test_login_accepted');
      if (redirectUrl) {
        location.assign(redirectUrl);
        return;
      }
      throw new Error('missing redirect');
    } catch (err) {
      trackError('qa_test_login_error', err);
      errorEl.textContent = err.message || t('Test login failed. Try again.');
      submit.disabled = false;
      submit.textContent = label;
    }
  };

  return el(
    'form',
    {
      class: 'qa-test-login',
      onsubmit: onSubmit,
      autocomplete: 'on',
      novalidate: '',
      'data-lpignore': 'true',
    },
    el('p', { class: 'hint' }, t('QA only — immediate sign-in for test email domains.')),
    el('label', { class: 'field-label', for: 'email-qa-test-login' }, t('Test email')),
    emailInput,
    submit,
    errorEl,
  );
}

function renderInviteEntryForm() {
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const input = el('input', {
    class: 'input',
    type: 'text',
    id: 'invite-entry',
    name: 'invite-code',
    placeholder: t('Iabc123 or https://…/invite/Iabc123'),
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
    el('label', { class: 'field-label', for: 'invite-entry' }, t('Invite link or code')),
    el(
      'p',
      { class: 'field-hint' },
      t('New here? Paste the invite link a friend sent you.'),
    ),
    input,
    el(
      'button',
      { type: 'submit', class: 'btn btn-primary' },
      t('Continue with invite'),
    ),
    errorEl,
  );
}

function isSignedInReturn() {
  return new URLSearchParams(location.search).get('signed_in') === '1';
}

// #601: the `?auth_error=` banner is shown once; drop the flag from the
// address bar after rendering so a reload does not show it again.
function clearAuthErrorFromUrl() {
  const clean = urlWithoutAuthError(location);
  if (clean == null) return;
  try {
    history.replaceState(history.state, '', clean);
  } catch (_) {
    /* sandboxed or old browser: the banner just shows again on reload */
  }
}

function signedInFlash() {
  if (!isSignedInReturn()) return null;
  return el(
    'p',
    { class: 'hint' },
    t('You are signed in. Open Tentura below to continue.'),
  );
}

// --- State renderers -------------------------------------------------------
function renderInvalid(p) {
  setState('invalid');
  setPageTitle(t('Invite link invalid — Tentura'));
  const msg =
    p.codeStatus === 'consumed'
      ? t('This invite has already been used.')
      : p.codeStatus === 'expired'
        ? t('This invite has expired.')
        : t('We couldn’t find this invite.');
  const rawCode = parseInviteCodeRaw();
  const showDashHint =
    inviteCodeHadTrailingDash(rawCode) ||
    (rawCode && !INVITE_CODE_PATTERN.test(rawCode) && rawCode.endsWith('-'));
  return el(
    'div',
    { class: 'content' },
    el('h1', {}, t('This invite link is no longer valid')),
    el('p', {}, msg),
    showDashHint
      ? el(
          'p',
          { class: 'hint hint-emphasis' },
          t('This link ends with a hyphen. Remove any trailing "-" and try again.'),
        )
      : null,
    el('p', { class: 'section-label' }, t('Try another invite')),
    renderInviteEntryForm(),
    el(
      'a',
      {
        class: 'btn btn-secondary',
        href: '/invite/',
        onclick: () => track('cta_invalid_back_to_entry'),
      },
      t('Back to invite entry'),
    ),
  );
}

function renderIsInviter(p) {
  setState('is-inviter');
  setPageTitle(t('Your invite — Tentura'));
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, t('This is your own invite')),
    el('p', {}, t('Share this link with someone you want to connect with.')),
    el(
      'button',
      {
        class: 'btn btn-secondary',
        type: 'button',
        onclick: async (e) => {
          track('cta_copy_own_invite');
          try {
            await navigator.clipboard.writeText(location.href);
            e.target.textContent = t('Link copied');
          } catch (_) {
            /* clipboard blocked in some webviews */
          }
        },
      },
      t('Copy invite link'),
    ),
    ctaOpenApp(),
  );
}

function renderAlreadyFriends(p) {
  setState('already-friends');
  const name = inviterName(p);
  if (isSignedInReturn()) {
    setPageTitle(t('You’re all set — Tentura'));
    return el(
      'div',
      { class: 'content' },
      beaconOverlay(p),
      el('h1', {}, t('You’re all set')),
      el(
        'p',
        {},
        t(
          'Your account is ready, and {name} is connected with you. Open Tentura to continue.',
          { name },
        ),
      ),
      ctaOpenApp(),
    );
  }
  setPageTitle(t('Connected with {name} — Tentura', { name }));
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, t('You’re connected with {name}', { name })),
    el('p', {}, t('Open Tentura to continue.')),
    ctaOpenApp(),
  );
}

function renderExistingUser(p) {
  setState('existing-user');
  setPageTitle(t('{name} invited you — Tentura', { name: inviterName(p) }));
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    el('h1', {}, t('{name} wants to connect', { name: inviterName(p) })),
    el('p', {}, t('Accept the invite in the app to become friends.')),
    ctaOpenAcceptInvite(),
  );
}

function renderAnonymous(p) {
  setState('anonymous');
  setPageTitle(t('{name} invited you — Tentura', { name: inviterName(p) }));
  const code = parseInviteCode();
  // U084: say what Tentura is and why the friend sent the link before
  // asking for an email address.
  const copy = inviteLandingCopy({
    inviterName: inviterName(p),
    hasRequest: Boolean(p.beacon),
    isPost: p.beacon?.kind === 'post',
    inApp: env.inApp,
  });
  // #601: a failed Google sign-in started here comes back to this invite
  // page with `?auth_error=`.
  const authError = isSignedInReturn() ? null : authErrorMessage(location.search);
  const authOptions = renderInviteAuthOptions(code);
  const { existingToggle, signInBlock } = createSignInReveal(code, {
    hideOnReveal: authOptions,
  });
  return el(
    'div',
    { class: 'content' },
    beaconOverlay(p),
    signedInFlash(),
    el('h1', {}, t('{name} invited you to Tentura', { name: inviterName(p) })),
    authError ? el('p', { class: 'error', role: 'alert' }, authError) : null,
    el('p', { class: 'invite-about' }, copy.about),
    el('p', {}, copy.why),
    copy.signUp ? el('p', {}, copy.signUp) : null,
    ...authOptions,
    existingToggle,
    signInBlock,
  );
}

const POST_JOIN_BEACON_KEY = 'tentura_post_join_beacon';

function persistPostJoinBeacon(p) {
  if (!p?.beacon?.id) return;
  try {
    sessionStorage.setItem(
      POST_JOIN_BEACON_KEY,
      JSON.stringify({
        id: p.beacon.id,
        title: p.beacon.title || '',
        kind: p.beacon.kind || 'request',
        inviterName: p.inviter?.displayName || '',
      }),
    );
  } catch (_) {
    /* blocked storage */
  }
}

function render(p) {
  persistPostJoinBeacon(p);
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
  setPageTitle(t('Something went wrong — Tentura'));
  card.replaceChildren(
    el(
      'div',
      { class: 'content' },
      el('h1', {}, t('Something went wrong')),
      el('p', {}, t('Please try opening this link again.')),
    ),
  );
}

// Landing visited with no `/invite/:code` — e.g. the WASM app bounced a
// logged-out / unauthenticated web user here (the app has no login UI). Tentura
// is invite-only, so there is no public signup; show a neutral message rather
// than the link-specific "Something went wrong" error.
function renderNoInvite() {
  setState('no-invite');

  const inviteIntro = el('p', {}, t('Join with a personal invite from someone you know.'));
  const inviteForm = renderInviteEntryForm();
  const heading = el('h1', {}, t('Tentura is invite-only'));
  const applyLandingMode = (signInMode) => {
    setPageTitle(signInMode ? t('Sign in — Tentura') : t('Tentura — invite-only'));
    heading.textContent = signInMode ? t('Sign in to Tentura') : t('Tentura is invite-only');
  };
  const { existingToggle, signInBlock } = createSignInReveal('', {
    expandedByDefault: true,
    onSignInModeChange: applyLandingMode,
  });
  applyLandingMode(true);
  // #418: a cancelled/failed Google sign-in comes back with `?auth_error=`.
  const authError = isSignedInReturn() ? null : authErrorMessage(location.search);

  const children = [
    el('p', { class: 'eyebrow' }, t('Private coordination network')),
    heading,
    inviteIntro,
    signedInFlash(),
    authError ? el('p', { class: 'error', role: 'alert' }, authError) : null,
    inviteForm,
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
    const rawCode = parseInviteCodeRaw();
    const code = parseInviteCode();
    initVisit({ env, hasCode: Boolean(code) });
    startAppPreload({ env, track });
    track('landing_view', { tier: env.tier, hasCode: Boolean(code) });

    if (isSignedInReturn()) {
      applyGoogleReturnAttemptId();
    }

    if (isSignedInReturn() && !isOnboardingDone(sessionStorage)) {
      const profile = await fetchMyProfile();
      if (profile && shouldRunPostSignup(location.search, sessionStorage, profile)) {
        setAccount(profile.id);
        track('post_signup_view', {
          hasCode: Boolean(code),
          nameOnly: !isNewSignupReturn(location.search),
        });
        renderPostSignup({
          card,
          profile,
          setState,
          setPageTitle,
          track,
          openProductUrl,
          storage: sessionStorage,
          nameOnly: !isNewSignupReturn(location.search),
        });
        return;
      }
      if (isNewSignupReturn(location.search)) {
        track('post_signup_fallback');
      }
    }

    if (rawCode && code && rawCode !== code && INVITE_CODE_PATTERN.test(code)) {
      const next = invitePathForCode(code) + location.search + location.hash;
      location.replace(next);
      return;
    }

    if (!code) {
      renderNoInvite();
      clearAuthErrorFromUrl();
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
    clearAuthErrorFromUrl();
  } catch (e) {
    const Sentry = window.Sentry;
    if (Sentry) Sentry.captureException(e);
    trackError('landing_boot_error', e);
    renderError();
  }
}

installBfcacheRefresh(window, main);
main();
