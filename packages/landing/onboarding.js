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

export const ONBOARDING_PAGES = [
  {
    title: 'Get things done through people you trust',
    body:
      'Tentura is where you ask for help and offer yours — no public feed, ' +
      'no likes, no noise. Just real needs moving through real people.',
  },
  {
    title: 'Light a beacon, friends pass it on',
    body:
      "Describe what you need — that's a beacon. Friends forward it to " +
      "someone who can help, and you coordinate in the beacon's room until " +
      "it's done.",
  },
  {
    title: 'Everyone here is vouched for',
    body:
      'You joined by a personal invite, like everyone else — the friend who ' +
      'invited you is already in your network. Add people you trust, and ' +
      'light a beacon when you need a hand.',
  },
];

/** `?signed_in=1&new=1` — fresh account just created by email/Google auth. */
export function isNewSignupReturn(search) {
  const params = new URLSearchParams(search || '');
  return params.get('signed_in') === '1' && params.get('new') === '1';
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
  } catch (e) {
    throw new Error(`Could not reach the server (${e}).`);
  }
  if (!res.ok) {
    let message = 'Could not save your name. You can change it later in the app.';
    try {
      const body = await res.json();
      if (body && typeof body.error === 'string') message = body.error;
    } catch {
      /* non-JSON error body */
    }
    throw new Error(message);
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
}) {
  setState('post-signup');
  setPageTitle('Welcome to Tentura');

  const showPager = () => {
    card.replaceChildren(
      renderOnboardingPager({ track, openProductUrl, storage }),
    );
  };

  card.replaceChildren(
    renderNameStep({
      prefill: (profile.displayName || '').trim(),
      track,
      onDone: showPager,
    }),
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
    maxlength: '32',
    autocomplete: 'off',
    'data-lpignore': 'true',
  });
  const errorEl = el('p', { class: 'error', role: 'alert' });
  const submit = el(
    'button',
    { class: 'btn btn-primary', type: 'submit' },
    'Save & continue',
  );

  const onSubmit = async (e) => {
    e.preventDefault();
    errorEl.textContent = '';
    const name = input.value.trim();
    if (name === prefill || name.length === 0) {
      track('signup_name_skipped', { reason: 'unchanged' });
      onDone();
      return;
    }
    submit.disabled = true;
    submit.textContent = 'Saving…';
    try {
      await saveDisplayName(name);
      track('signup_name_saved');
      onDone();
    } catch (err) {
      trackError('signup_name_error', err);
      errorEl.textContent = err.message;
      submit.disabled = false;
      submit.textContent = 'Save & continue';
    }
  };

  const skip = el(
    'button',
    { class: 'hint hint-link', type: 'button' },
    'Skip for now',
  );
  skip.addEventListener('click', () => {
    track('signup_name_skipped', { reason: 'skip' });
    onDone();
  });

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
      submit,
      errorEl,
    ),
    skip,
  );
}

function renderOnboardingPager({ track, openProductUrl, storage }) {
  let page = 0;

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
    'Open Tentura',
  );
  openApp.addEventListener('click', () => {
    markOnboardingDone(storage);
    track('onboarding_done');
  });

  const skip = el(
    'button',
    { class: 'hint hint-link', type: 'button' },
    'Skip — open Tentura',
  );
  skip.addEventListener('click', () => {
    markOnboardingDone(storage);
    track('onboarding_skipped', { page: page + 1 });
    location.assign(openProductUrl());
  });

  const show = (index) => {
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
    back.hidden = page === 0;
    const isLast = page === ONBOARDING_PAGES.length - 1;
    next.hidden = isLast;
    next.textContent = 'Next';
    openApp.hidden = !isLast;
    track('onboarding_view', { page: page + 1 });
  };

  back.addEventListener('click', () => show(page - 1));
  next.addEventListener('click', () => show(page + 1));
  show(0);

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
