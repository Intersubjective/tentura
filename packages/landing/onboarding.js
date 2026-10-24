// Post-signup flow on the static landing: display-name step + 3-page
// onboarding pager. Shown when auth redirects back with `?signed_in=1&new=1`
// (brand-new account). While the user reads these pages, app_preload.js keeps
// warming WASM assets in the background, so "Open Tentura" boots from cache.
//
// Profile reads/writes use the cookie-auth REST endpoint
// (`/api/v2/accounts/me/profile`, `credentials: 'include'`); landing JS never
// handles JWTs.

import { trackError } from './analytics.js';

// '' = same origin; window guard keeps the module importable under node:test.
const API_BASE =
  (typeof window !== 'undefined' && (window.TENTURA || {}).apiBase) || '';

const DONE_KEY = 'tentura_post_signup_done';
/** Per tab session: the account whose name step is behind it (holds its id). */
const NAME_DONE_KEY = 'tentura_post_signup_name_done';

export const ONBOARDING_PAGES = [
  {
    title: 'Get things done through people you trust',
    body:
      'Tentura is where you ask for help and offer yours — no public feed, ' +
      'no likes, no noise. Just real needs moving through real people.',
  },
  {
    title: 'Post a request, friends pass it on',
    body:
      "Describe what you need — that's a request. Friends forward it to " +
      "someone who can help, and you coordinate in the request's discussion until " +
      "it's done.",
  },
  {
    title: 'Everyone here is vouched for',
    body:
      'You joined by a personal invite, like everyone else — the friend who ' +
      'invited you is already in your network. Add people you trust, and ' +
      'post a request when you need a hand.',
  },
];

/** Label of the seed-recovery text link on the signed-out pages (U084). */
export const RECOVER_SEED_LINK_LABEL =
  'Restore an account from your recovery seed';

/** One sentence about Tentura for the invite landing: the first sentence of
 * the first onboarding page, so both say the same thing (U084). */
export const INVITE_ABOUT_SENTENCE =
  'Tentura is where you ask for help and offer yours — no public feed, ' +
  'no likes, no noise.';

/**
 * Copy for the invite landing a signed-out person sees (U084): one sentence
 * about what Tentura is and one about why the friend sent the link, without
 * leading with seed recovery. On a request-scoped invite the request card is
 * already above (inviter + title), so the why line points at it instead of
 * repeating it. `signUp` is only set inside an in-app browser, where the
 * person must be told to open the link elsewhere; otherwise the "Get started"
 * label and the buttons already say how to join.
 * A Post-scoped invite (`isPost`) points at the post card and never says
 * "request" (#501).
 * @param {{ inviterName: string, hasRequest?: boolean, isPost?: boolean, inApp: boolean }} args
 */
export function inviteLandingCopy({
  inviterName,
  hasRequest = false,
  isPost = false,
  inApp,
}) {
  let why;
  if (hasRequest && isPost) {
    why =
      `${inviterName} shared the post above with you. ` +
      'Join to read it and reply in its chat.';
  } else if (hasRequest) {
    why =
      `${inviterName} wants your help with the request above. ` +
      'Join to see it, offer help or pass it on.';
  } else {
    why =
      `${inviterName} wants you in their network, ` +
      'so you can ask each other for a hand.';
  }
  return {
    about: INVITE_ABOUT_SENTENCE,
    why,
    signUp: inApp
      ? 'Open this link in your browser, or create an account with email.'
      : null,
    recoverLink: RECOVER_SEED_LINK_LABEL,
  };
}

/** `?signed_in=1` — session cookie set after email/OAuth auth. */
export function isSignedInReturn(search) {
  return new URLSearchParams(search || '').get('signed_in') === '1';
}

/**
 * `?auth_error=google_cancelled|google_failed` — the server sent a failed
 * Google sign-in back to the start page (#418). Returns the line to show, or
 * null. Only our own known values map to text; anything else shows nothing.
 */
export function authErrorMessage(search) {
  const reason = new URLSearchParams(search || '').get('auth_error');
  if (reason === 'google_cancelled') {
    return 'Google sign-in was cancelled.';
  }
  if (reason === 'google_failed') {
    return 'Google sign-in failed. Please try again.';
  }
  return null;
}

/**
 * #601: the current address (path + search + hash) with `auth_error` taken
 * out of the query, so a reload does not show the failed sign-in banner
 * again. Other params and the hash stay as they were. Returns null when there
 * is no `auth_error` param (nothing to rewrite).
 */
export function urlWithoutAuthError({ pathname = '/', search = '', hash = '' } = {}) {
  const params = new URLSearchParams(search || '');
  if (!params.has('auth_error')) return null;
  params.delete('auth_error');
  const rest = params.toString();
  return `${pathname || '/'}${rest ? `?${rest}` : ''}${hash || ''}`;
}

/** `?signed_in=1&new=1` — fresh account just created by email/Google auth. */
export function isNewSignupReturn(search) {
  const params = new URLSearchParams(search || '');
  return params.get('signed_in') === '1' && params.get('new') === '1';
}

/**
 * Name the server gives a new email account until the person picks one
 * (server kNewMemberDisplayName, #660). Older accounts may still carry an
 * email-derived name, matched by the heuristics below.
 */
const NEW_MEMBER_DISPLAY_NAME = 'New member';

/**
 * How the invite landing names the inviter: "Someone" when there is no name,
 * "A friend" for a placeholder ("New member", #660) or an older
 * email-derived name, else the name itself.
 */
export function inviterDisplayName(displayName) {
  const raw = String(displayName ?? '').trim();
  if (!raw) return 'Someone';
  if (raw === NEW_MEMBER_DISPLAY_NAME || isLikelyEmailDerivedDisplayName(raw)) {
    return 'A friend';
  }
  return raw;
}

/** Matches server displayNameFromEmail: lowercase alnum tokens separated by spaces. */
function isLikelyEmailDerivedDisplayName(name) {
  if (!name || name.length > 50 || /[A-Z]/.test(name)) return false;
  return /^[a-z0-9]+( [a-z0-9]+)*$/.test(name) && /\d/.test(name);
}

/**
 * Placeholder display names from email local-parts are lowercase and often
 * contain digits (e.g. agent-3c4703tb@test… → "agent 3c4703tb").
 */
export function isLikelyAutoDerivedDisplayName(displayName) {
  const t = String(displayName ?? '').trim();
  if (t.length === 0 || t === NEW_MEMBER_DISPLAY_NAME) return true;
  if (t !== t.toLowerCase()) return false;
  return /\d/.test(t);
}

/**
 * Server displayNameFromEmail output: the normalized (lowercase) email
 * local-part with [._+-] turned into spaces, so lowercase ASCII only, with
 * any other local-part characters (`_`, `%`, …) left in. Such a name is not
 * put in the name field (#422); a name with capitals or non-ASCII letters is
 * treated as chosen by the person and kept.
 */
function isLikelyEmailLocalPartName(displayName) {
  const t = String(displayName ?? '').trim();
  if (t.length === 0 || t === NEW_MEMBER_DISPLAY_NAME) return true;
  return /^[a-z0-9 !#$%&'*/=?^_`{|}~]+$/.test(t);
}

/**
 * Post-signup name step (+ pager for brand-new accounts) when the session is
 * signed in, onboarding is not done, and the account still has a placeholder name.
 */
export function shouldRunPostSignup(search, storage, profile) {
  if (!profile || isOnboardingDone(storage)) return false;
  if (!isSignedInReturn(search)) return false;
  if (isNewSignupReturn(search)) return true;
  return isLikelyAutoDerivedDisplayName(profile.displayName);
}

/** One-shot guard: reload/back after finishing must not replay onboarding. */
export function isOnboardingDone(storage) {
  try {
    return storage.getItem(DONE_KEY) === '1';
  } catch {
    return false;
  }
}

export function markOnboardingDone(storage) {
  try {
    storage.setItem(DONE_KEY, '1');
  } catch {
    /* storage blocked — flow still works, may replay on reload */
  }
}

/**
 * Reload, or browser Back then Forward, reopens `?signed_in=1&new=1`; once
 * this account's name was saved or skipped, the flow resumes at the pager
 * instead of showing the saved name in the name form again (#522).
 */
export function isNameStepDone(storage, accountId) {
  try {
    return accountId != null && storage.getItem(NAME_DONE_KEY) === accountId;
  } catch {
    return false;
  }
}

export function markNameStepDone(storage, accountId) {
  try {
    storage.setItem(NAME_DONE_KEY, accountId);
  } catch {
    /* storage blocked — a reload shows the name step again */
  }
}

/**
 * Current profile via session cookie. Returns `{id, displayName}` or null on
 * 401/network failure — null means "render the normal landing instead"
 * (replayed or shared `new=1` URLs are harmless).
 */
export async function fetchMyProfile() {
  try {
    const res = await fetch(`${API_BASE}/api/v2/accounts/me/profile`, {
      headers: { Accept: 'application/json' },
      credentials: 'include',
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/** PATCH the display name; throws Error with a user-facing message. */
export async function saveDisplayName(name) {
  let res;
  try {
    res = await fetch(`${API_BASE}/api/v2/accounts/me/profile`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ displayName: name }),
    });
  } catch {
    // The raw fetch error ("TypeError: Failed to fetch") means nothing to a
    // person (#660 review).
    throw new Error(
      'Could not reach the server. Check your connection and try again.',
    );
  }
  if (!res.ok) {
    // The server's error body is developer text ("displayName must be …"),
    // so it is not shown as is.
    throw new Error(
      res.status === 400
        ? 'That name could not be saved. Use 3 to 32 characters and try again.'
        : 'Could not save your name. Try again.',
    );
  }
  return res.json();
}

// --- DOM (kept local; main.js's `el` is not importable without a cycle) -----
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

/**
 * Render name step → onboarding pager into [card].
 * @param {{
 *   card: HTMLElement,
 *   profile: { id: string, displayName?: string },
 *   setState: (name: string) => void,
 *   setPageTitle: (title: string) => void,
 *   track: (name: string, data?: object) => void,
 *   openProductUrl: () => string,
 *   storage: Storage,
 *   nameOnly?: boolean,
 * }} deps
 */
export function renderPostSignup({
  card,
  profile,
  setState,
  setPageTitle,
  track,
  openProductUrl,
  storage,
  nameOnly = false,
}) {
  setState('post-signup');
  setPageTitle('Welcome to Tentura');

  let currentName = (profile.displayName || '').trim();

  const showPager = () => {
    card.replaceChildren(
      renderOnboardingPager({
        track,
        openProductUrl,
        storage,
      }),
    );
  };

  const finish = (savedName) => {
    if (typeof savedName === 'string') currentName = savedName;
    markNameStepDone(storage, profile.id);
    if (nameOnly) {
      markOnboardingDone(storage);
      card.replaceChildren(
        renderOpenAppPrompt({ openProductUrl, track, storage }),
      );
      return;
    }
    showPager();
  };

  if (!nameOnly && isNameStepDone(storage, profile.id)) {
    showPager();
    return;
  }
  card.replaceChildren(
    renderNameStep({
      prefill: isLikelyEmailLocalPartName(currentName) ? '' : currentName,
      track,
      onDone: finish,
    }),
  );
}

function renderOpenAppPrompt({ openProductUrl, track, storage }) {
  const openApp = el(
    'a',
    { class: 'btn btn-primary', href: openProductUrl() },
    'Continue to Tentura',
  );
  openApp.addEventListener('click', () => {
    markOnboardingDone(storage);
    track('onboarding_done', { nameOnly: true });
  });
  return el(
    'div',
    { class: 'content' },
    el('h1', {}, 'You’re all set'),
    el('p', {}, 'Open Tentura to continue.'),
    openApp,
  );
}

function renderNameStep({ prefill, track, onDone }) {
  track('signup_name_view');

  const input = el('input', {
    class: 'input',
    type: 'text',
    id: 'display-name',
    name: 'display-name',
    value: prefill,
    placeholder: 'e.g. Anna K.',
    maxlength: '32',
    autocomplete: 'off',
    'data-lpignore': 'true',
    'aria-describedby': 'display-name-hint',
  });
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const submit = el(
    'button',
    { class: 'btn btn-primary', type: 'submit' },
    'Save & continue',
  );

  // Shown once a save fails: with Skip gone (#660) a person who is offline,
  // or whose name keeps being rejected, still has a way on. The account keeps
  // the server placeholder "New member" and the app asks for a name later.
  const continueWithoutName = el(
    'button',
    { class: 'btn btn-secondary name-continue', type: 'button' },
    'Continue without a name',
  );
  continueWithoutName.hidden = true;
  continueWithoutName.addEventListener('click', () => {
    track('signup_name_skipped', { reason: 'save_failed' });
    onDone();
  });

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    const name = input.value.trim();
    // An empty Save used to move on like Skip, saving nothing (#421).
    if (name.length === 0) {
      errorEl.textContent = 'Enter a name.';
      input.focus();
      return;
    }
    if (name === prefill) {
      track('signup_name_skipped', { reason: 'unchanged' });
      onDone();
      return;
    }
    submit.disabled = true;
    submit.textContent = 'Saving…';
    try {
      await saveDisplayName(name);
      track('signup_name_saved');
      onDone(name);
    } catch (err) {
      trackError('signup_name_error', err);
      errorEl.textContent = err.message;
      submit.disabled = false;
      submit.textContent = 'Try again';
      continueWithoutName.hidden = false;
    }
  };

  return el(
    'div',
    { class: 'content' },
    el('p', { class: 'eyebrow' }, 'Account created'),
    el('h1', {}, 'Welcome to Tentura'),
    el('p', {}, 'What should people call you?'),
    el(
      'form',
      { class: 'signup-form', onsubmit: onSubmit, autocomplete: 'off' },
      el('label', { class: 'field-label', for: 'display-name' }, 'Your name'),
      input,
      el(
        'p',
        { class: 'hint name-change-hint', id: 'display-name-hint' },
        'You can change your name any time in Profile.',
      ),
      submit,
      errorEl,
      continueWithoutName,
    ),
  );
}

// #522: each pager step is its own session-history entry, so the browser
// Back/Forward buttons move between steps instead of leaving the flow.
const PAGER_HISTORY_KEY = 'tenturaOnboardingPage';
let detachPagerHistory = null;

function pagerHistory() {
  const h = globalThis.history;
  if (
    !h ||
    typeof h.pushState !== 'function' ||
    typeof globalThis.addEventListener !== 'function'
  ) {
    return null;
  }
  return h;
}

function pageFromHistoryState(state) {
  const page = state?.[PAGER_HISTORY_KEY];
  return Number.isInteger(page) ? page : null;
}

function writePagerHistory(nav, page, { push }) {
  const state = { ...(nav.state ?? {}), [PAGER_HISTORY_KEY]: page };
  try {
    if (push) {
      nav.pushState(state, '');
    } else {
      nav.replaceState(state, '');
    }
  } catch (_) {
    /* sandboxed or old browser: browser Back just leaves the flow */
  }
}

function renderOnboardingPager({ track, openProductUrl, storage }) {
  let page = 0;
  const nav = pagerHistory();
  // Set below when this pager listens to browser Back/Forward.
  let detachOwnHistory = null;
  // Leaving the flow (Continue or Skip) drops this pager's popstate
  // listener; a re-render drops it too (detachPagerHistory).
  const finishPagerHistory = () => {
    if (!detachOwnHistory) return;
    detachOwnHistory();
    if (detachPagerHistory === detachOwnHistory) detachPagerHistory = null;
    detachOwnHistory = null;
  };

  const title = el('h1', {});
  const body = el('p', {});
  const progress = el('p', { class: 'hint pager-progress' });
  const dots = el('div', { class: 'pager-dots' });
  const back = el(
    'button',
    { class: 'btn btn-secondary pager-back', type: 'button' },
    'Back',
  );
  const next = el('button', { class: 'btn btn-primary', type: 'button' });

  const openApp = el(
    'a',
    { class: 'btn btn-primary', href: openProductUrl() },
    'Continue to Tentura',
  );
  openApp.addEventListener('click', () => {
    markOnboardingDone(storage);
    finishPagerHistory();
    track('onboarding_done');
  });

  const skip = el(
    'button',
    { class: 'hint hint-link', type: 'button' },
    'Skip — open Tentura',
  );
  skip.addEventListener('click', () => {
    markOnboardingDone(storage);
    finishPagerHistory();
    track('onboarding_skipped', { page: page + 1 });
    location.assign(openProductUrl());
  });

  const show = (index) => {
    const focused = globalThis.document?.activeElement;
    // Clamp: defense against a stray click on a control that should be
    // hidden — never step past the last page.
    page = Math.max(0, Math.min(index, ONBOARDING_PAGES.length - 1));
    const p = ONBOARDING_PAGES[page];
    title.textContent = p.title;
    body.textContent = p.body;
    progress.textContent = `Step ${page + 1} of ${ONBOARDING_PAGES.length}`;
    dots.replaceChildren(
      ...ONBOARDING_PAGES.map((_, i) =>
        el('span', { class: i === page ? 'pager-dot active' : 'pager-dot' }),
      ),
    );
    const isLast = page === ONBOARDING_PAGES.length - 1;
    // U085: the name is already saved, and the name step says it can be
    // changed in Profile — so step 1 has nothing to go back to.
    back.hidden = page === 0;
    next.hidden = isLast;
    next.textContent = 'Next';
    openApp.hidden = !isLast;
    // On the last page Continue is the exit; a Skip beside it did the same.
    skip.hidden = isLast;
    // Hiding the focused control drops focus to <body>; keep keyboard and
    // screen-reader users on the step's forward control instead.
    if (
      (focused === back && back.hidden) ||
      (focused === next && next.hidden) ||
      (focused === skip && skip.hidden)
    ) {
      (isLast ? openApp : next).focus();
    }
    track('onboarding_view', { page: page + 1 });
  };

  back.addEventListener('click', () => {
    // Our own entry for this step sits on top of the previous step's: go
    // back through history so browser Back/Forward stay in step.
    if (nav && page > 0 && pageFromHistoryState(nav.state) === page) {
      nav.back();
      return;
    }
    show(page - 1);
  });
  next.addEventListener('click', () => {
    show(page + 1);
    if (nav) writePagerHistory(nav, page, { push: true });
  });

  if (nav) {
    detachPagerHistory?.();
    const onPopState = (e) => {
      const target = pageFromHistoryState(e.state);
      // Not one of our entries: leave it to the page.
      if (target != null) show(target);
    };
    globalThis.addEventListener('popstate', onPopState);
    detachOwnHistory = () =>
      globalThis.removeEventListener?.('popstate', onPopState);
    detachPagerHistory = detachOwnHistory;
    // Reload keeps the entry's state: resume at that step.
    show(pageFromHistoryState(nav.state) ?? 0);
    writePagerHistory(nav, page, { push: false });
  } else {
    show(0);
  }

  return el(
    'div',
    { class: 'content pager' },
    el('div', { class: 'pager-page' }, title, body),
    progress,
    dots,
    next,
    openApp,
    back,
    skip,
  );
}
