import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  ONBOARDING_PAGES,
  isNewSignupReturn,
  isOnboardingDone,
  markOnboardingDone,
  shouldRunPostSignup,
} from '../onboarding.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const onboardingJs = readFileSync(join(root, 'onboarding.js'), 'utf8');
const mainJs = readFileSync(join(root, 'main.js'), 'utf8');

function fakeStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
  };
}

test('isNewSignupReturn requires both signed_in and new flags', () => {
  assert.equal(isNewSignupReturn('?signed_in=1&new=1'), true);
  assert.equal(isNewSignupReturn('?new=1&signed_in=1'), true);
  assert.equal(isNewSignupReturn('?signed_in=1'), false);
  assert.equal(isNewSignupReturn('?new=1'), false);
  assert.equal(isNewSignupReturn(''), false);
  assert.equal(isNewSignupReturn('?signed_in=0&new=1'), false);
});

test('onboarding done flag round-trips through storage', () => {
  const storage = fakeStorage();
  assert.equal(isOnboardingDone(storage), false);
  markOnboardingDone(storage);
  assert.equal(isOnboardingDone(storage), true);
});

test('storage helpers swallow blocked-storage errors', () => {
  const broken = {
    getItem: () => {
      throw new Error('blocked');
    },
    setItem: () => {
      throw new Error('blocked');
    },
  };
  assert.equal(isOnboardingDone(broken), false);
  assert.doesNotThrow(() => markOnboardingDone(broken));
});

test('onboarding has exactly 3 short pages', () => {
  assert.equal(ONBOARDING_PAGES.length, 3);
  for (const page of ONBOARDING_PAGES) {
    assert.ok(page.title.length > 0);
    assert.ok(page.body.length > 0, 'page body present');
    assert.ok(page.body.length < 300, 'pages stay elevator-pitch short');
  }
});

test('profile API uses cookie-auth REST, never JWTs', () => {
  assert.match(onboardingJs, /\/api\/v2\/accounts\/me\/profile/);
  const profileCalls = onboardingJs.match(/credentials: 'include'/g) || [];
  assert.ok(profileCalls.length >= 2, 'GET and PATCH send the session cookie');
  assert.doesNotMatch(onboardingJs, /access-token/);
  assert.doesNotMatch(onboardingJs, /Authorization/);
  assert.doesNotMatch(onboardingJs, /Bearer/);
});

test('profile fetch returns null on failure (replay-safe)', () => {
  assert.match(onboardingJs, /if \(!res\.ok\) return null;/);
  assert.match(onboardingJs, /catch \{\s*return null;/);
});

test('main.js gates post-signup on signed-in return and falls back', () => {
  assert.match(
    mainJs,
    /isSignedInReturn\(\) && !isOnboardingDone\(sessionStorage\)/,
  );
  assert.match(mainJs, /shouldRunPostSignup\(location\.search, sessionStorage, profile\)/);
  // 401/no-profile falls through to the normal render (replayed URL safety).
  assert.match(mainJs, /post_signup_fallback/);
  // Post-signup check runs before the no-code branch so `/invite/?new=1` works.
  assert.ok(
    mainJs.indexOf('shouldRunPostSignup') < mainJs.indexOf('renderNoInvite()'),
  );
});

test('shouldRunPostSignup covers new signup and placeholder names', () => {
  const storage = fakeStorage();
  const profile = { id: 'U1', displayName: 'agent 3c4703tb' };
  assert.equal(
    shouldRunPostSignup('?signed_in=1&new=1', storage, profile),
    true,
  );
  assert.equal(
    shouldRunPostSignup('?signed_in=1', storage, profile),
    true,
  );
  assert.equal(
    shouldRunPostSignup('?signed_in=1', storage, {
      id: 'U1',
      displayName: 'Ada Lovelace',
    }),
    false,
  );
  markOnboardingDone(storage);
  assert.equal(
    shouldRunPostSignup('?signed_in=1&new=1', storage, profile),
    false,
  );
});

test('pager marks done before opening the product', () => {
  assert.match(onboardingJs, /markOnboardingDone\(storage\)/);
  assert.match(onboardingJs, /onboarding_done/);
  assert.match(onboardingJs, /onboarding_skipped/);
});

test('main.js persists post-join beacon on preview render', () => {
  assert.match(mainJs, /function persistPostJoinBeacon\(p\)/);
  assert.match(mainJs, /POST_JOIN_BEACON_KEY/);
  assert.match(mainJs, /persistPostJoinBeacon\(p\)/);
  assert.match(mainJs, /inviterName: p\.inviter\?\.displayName/);
});

test('pager exposes explicit textual progress', () => {
  assert.match(
    onboardingJs,
    /progress\.textContent = `Step \$\{page \+ 1\} of \$\{ONBOARDING_PAGES\.length\}`/,
  );
  assert.match(onboardingJs, /class: 'hint pager-progress'/);
});

test('email success state tells the user to check email and relabels submit', () => {
  assert.match(mainJs, /'Check your email'/);
  assert.match(mainJs, /successEl\.hidden = false/);
  assert.match(mainJs, /emailInput\.disabled = true/);
  assert.match(mainJs, /Link sent — check your email/);
});

test('pager clamps page index and hidden controls actually hide', () => {
  // show() must never step past the last page even if a hidden control fires.
  assert.match(onboardingJs, /Math\.max\(0, Math\.min\(index, ONBOARDING_PAGES\.length - 1\)\)/);
  // `.btn { display: block }` outranks the UA [hidden] rule; the stylesheet
  // must restore it or `next.hidden = true` leaves Next visible on page 3.
  const css = readFileSync(join(root, 'styles.css'), 'utf8');
  assert.match(css, /\[hidden\]\s*\{\s*display:\s*none\s*!important;?\s*\}/);
});

test('U085: pager hides Back on the first slide (the name is already saved)', () => {
  assert.match(onboardingJs, /back\.hidden\s*=\s*page\s*===\s*0/);
  // No path from the pager back into the name step any more.
  assert.doesNotMatch(onboardingJs, /onBackFromFirstPage/);
});

test('U085: the name step says the name can be changed later in Profile', () => {
  assert.match(onboardingJs, /You can change your name any time in Profile\./);
});

/**
 * Minimal DOM stub for el()/renderPostSignup — enough for createElement,
 * attributes, events, append, and replaceChildren. No jsdom (landing has no npm).
 */
function installDomFake() {
  class FakeNode {
    constructor(nodeType, tagName = '') {
      this.nodeType = nodeType;
      this.tagName = tagName;
      this.children = [];
      this.attrs = {};
      this.listeners = {};
      this.className = '';
      this._text = '';
      this._value = '';
      this.hidden = false;
      this.disabled = false;
    }
    setAttribute(k, v) {
      this.attrs[k] = String(v);
      if (k === 'value') this._value = String(v);
    }
    getAttribute(k) {
      return this.attrs[k] ?? null;
    }
    addEventListener(type, fn) {
      (this.listeners[type] ??= []).push(fn);
    }
    append(...nodes) {
      for (const n of nodes) {
        if (n == null) continue;
        this.children.push(n);
        if (n.nodeType === 3) this._text += n.data;
      }
    }
    replaceChildren(...nodes) {
      this.children = [];
      this._text = '';
      this.append(...nodes);
    }
    get textContent() {
      if (this.nodeType === 3) return this.data;
      return this.children.map((c) => c.textContent).join('');
    }
    set textContent(v) {
      this.children = [];
      this._text = String(v);
      if (v) this.children.push(new FakeNode(3));
      if (this.children[0]) this.children[0].data = String(v);
    }
    get value() {
      return this._value;
    }
    set value(v) {
      this._value = String(v);
      this.attrs.value = String(v);
    }
    focus() {
      this._focused = true;
      globalThis.document.activeElement = this;
    }
    querySelector(sel) {
      if (sel.startsWith('#')) {
        const id = sel.slice(1);
        return this._find((n) => n.attrs.id === id);
      }
      if (sel.startsWith('.')) {
        const cls = sel.slice(1);
        return this._find(
          (n) =>
            n.className === cls ||
            String(n.className).split(/\s+/).includes(cls),
        );
      }
      const tag = sel.toUpperCase();
      return this._find((n) => n.tagName === tag);
    }
    querySelectorAll(sel) {
      const out = [];
      this._walk((n) => {
        if (sel.startsWith('.')) {
          const cls = sel.slice(1);
          if (
            n.className === cls ||
            String(n.className).split(/\s+/).includes(cls)
          ) {
            out.push(n);
          }
        } else if (n.tagName === sel.toUpperCase()) {
          out.push(n);
        }
      });
      return out;
    }
    _find(pred) {
      let found = null;
      this._walk((n) => {
        if (!found && pred(n)) found = n;
      });
      return found;
    }
    _walk(fn) {
      fn(this);
      for (const c of this.children) {
        if (c._walk) c._walk(fn);
      }
    }
    click() {
      for (const fn of this.listeners.click || []) fn({ preventDefault() {} });
    }
    submit() {
      for (const fn of this.listeners.submit || [])
        fn({ preventDefault() {} });
    }
  }

  globalThis.document = {
    createElement(tag) {
      return new FakeNode(1, tag.toUpperCase());
    },
    createTextNode(text) {
      const n = new FakeNode(3);
      n.data = String(text);
      return n;
    },
  };
  return FakeNode;
}

test('U085: save name, then the pager starts with no Back; Back on step 2 returns to step 1', async () => {
  installDomFake();
  const events = [];
  let patchedName = null;
  globalThis.fetch = async (url, init) => {
    if (init?.method === 'PATCH') {
      patchedName = JSON.parse(init.body).displayName;
      return {
        ok: true,
        json: async () => ({ id: 'U1', displayName: patchedName }),
      };
    }
    return { ok: true, json: async () => ({}) };
  };
  globalThis.window = globalThis;

  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  const storage = fakeStorage();

  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'agent 3c4703tb' },
    setState: () => {},
    setPageTitle: () => {},
    track: (name, data) => events.push({ name, data }),
    openProductUrl: () => '/app/',
    storage,
    nameOnly: false,
  });

  const input = card.querySelector('#display-name');
  assert.ok(input);
  // #422: the email-derived placeholder name is not put in the field.
  assert.equal(input.value, '');
  input.value = 'Ada Lovelace';
  const form = card.querySelector('FORM');
  form.submit();
  // Allow the async PATCH + onDone to settle.
  await new Promise((r) => setTimeout(r, 0));
  await new Promise((r) => setTimeout(r, 0));

  assert.equal(patchedName, 'Ada Lovelace');
  assert.ok(card.querySelector('.pager'));
  assert.ok(
    events.some((e) => e.name === 'signup_name_saved'),
    'saved event fired',
  );

  const back = card.querySelector('.pager-back');
  assert.ok(back);
  assert.equal(back.hidden, true, 'no Back on step 1');

  const next = card.querySelector('.btn-primary');
  next.click();
  assert.equal(back.hidden, false, 'Back shows from step 2');
  back.click();
  assert.equal(back.hidden, true, 'back on step 1');
  assert.equal(card.querySelector('#display-name'), null, 'name step not re-rendered');
  assert.ok(!events.some((e) => e.name === 'onboarding_back'));
});

test('#522 review: hiding the focused Back moves focus to Next', async () => {
  installDomFake();
  globalThis.window = globalThis;
  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  const storage = fakeStorage({ tentura_post_signup_name_done: 'U1' });
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'Ada' },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage,
  });

  const next = card.querySelector('.btn-primary');
  next.click();
  const back = card.querySelector('.pager-back');
  back.focus();
  back.click();

  assert.equal(back.hidden, true);
  assert.equal(document.activeElement, next, 'focus did not fall to <body>');
});

test('#522 review: reload after the name step resumes at the pager', async () => {
  installDomFake();
  globalThis.window = globalThis;
  const { renderPostSignup } = await import('../onboarding.js');
  const storage = fakeStorage();
  const render = (card) =>
    renderPostSignup({
      card,
      profile: { id: 'U1', displayName: 'agent 3c4703tb' },
      setState: () => {},
      setPageTitle: () => {},
      track: () => {},
      openProductUrl: () => '/app/',
      storage,
    });

  const first = document.createElement('div');
  render(first);
  first.querySelector('.hint-link').click(); // Skip for now
  assert.ok(first.querySelector('.pager'));

  // Same tab session, same ?signed_in=1&new=1 URL (reload / Back+Forward).
  const reloaded = document.createElement('div');
  render(reloaded);
  assert.ok(reloaded.querySelector('.pager'), 'resumes at the pager');
  assert.equal(reloaded.querySelector('#display-name'), null);

  // Another account in the same tab still gets its name step.
  const other = document.createElement('div');
  renderPostSignup({
    card: other,
    profile: { id: 'U2', displayName: 'agent 99x' },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage,
  });
  assert.ok(other.querySelector('#display-name'));
});

test('#522 review: the name hint is linked to the field', () => {
  assert.match(onboardingJs, /'aria-describedby': 'display-name-hint'/);
  assert.match(onboardingJs, /id: 'display-name-hint'/);
  assert.doesNotMatch(onboardingJs, /revisit/);
});

// #424: on the last page "Continue to Tentura" and "Skip — open Tentura"
// both opened the product.
test('pager hides Skip on the last page, where Continue is the exit', async () => {
  installDomFake();
  globalThis.fetch = async () => ({ ok: true, json: async () => ({}) });
  globalThis.window = globalThis;

  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'Ada' },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage: fakeStorage(),
    nameOnly: false,
  });
  // Unchanged name: straight to the pager.
  card.querySelector('FORM').submit();
  await new Promise((r) => setTimeout(r, 0));

  const pager = card.querySelector('.pager');
  assert.ok(pager);
  const skip = pager.querySelector('.hint-link');
  const next = pager
    .querySelectorAll('BUTTON')
    .find((b) => b.textContent === 'Next');
  assert.equal(skip.hidden, false, 'Skip offered on page 1');
  for (let i = 1; i < ONBOARDING_PAGES.length; i++) next.click();
  assert.equal(skip.hidden, true, 'no Skip next to Continue on the last page');
});

// #421: "Save & continue" with the name cleared moved on like Skip, saving
// nothing and saying nothing.
test('an empty name asks for a name instead of moving on', async () => {
  installDomFake();
  let patched = false;
  globalThis.fetch = async (url, init) => {
    if (init?.method === 'PATCH') patched = true;
    return { ok: true, json: async () => ({}) };
  };
  globalThis.window = globalThis;

  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  const events = [];
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'agent 3c4703tb' },
    setState: () => {},
    setPageTitle: () => {},
    track: (name) => events.push(name),
    openProductUrl: () => '/app/',
    storage: fakeStorage(),
    nameOnly: false,
  });
  card.querySelector('#display-name').value = '   ';
  card.querySelector('FORM').submit();
  await new Promise((r) => setTimeout(r, 0));

  assert.equal(card.querySelector('.pager'), null, 'still on the name step');
  assert.equal(patched, false);
  assert.ok(!events.includes('signup_name_skipped'));
  assert.match(card.querySelector('.error').textContent, /Enter a name/);
});

// #422: the server names a new email account after the email local-part
// (displayNameFromEmail: `tab.qa.01@x` -> "tab qa 01"). The name step must
// not hand that back as the field value; it shows an empty field with an
// example placeholder instead. A real name (e.g. from Google) stays prefilled.
async function renderNameStepFor(displayName, { nameOnly = false } = {}) {
  installDomFake();
  globalThis.window = globalThis;
  globalThis.fetch = async () => ({ ok: true, json: async () => ({}) });
  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage: fakeStorage(),
    nameOnly,
  });
  const input = card.querySelector('#display-name');
  assert.ok(input, 'name step rendered');
  return { card, input };
}

// 'tab_qa_01': the server only turns [._+-] into spaces, so `_` (and `%`)
// survive in the derived name. 'vadim': a single lowercase token is
// intentionally not prefilled, even though a real user could have typed it.
for (const derived of ['tab qa 01', 'agent 3c4703tb', 'ada lovelace', 'vadim', 'tab_qa_01']) {
  test(`#422: email-derived name "${derived}" is not prefilled`, async () => {
    const { input } = await renderNameStepFor(derived);
    assert.equal(input.value, '');
    assert.equal(input.getAttribute('value') ?? '', '');
  });
}

test('#422: the empty name field shows an example placeholder', async () => {
  const { input } = await renderNameStepFor('tab qa 01');
  assert.equal(input.getAttribute('placeholder'), 'e.g. Anna K.');
});

test('#422: the name-only step for a returning account is not prefilled either', async () => {
  const { input } = await renderNameStepFor('tab qa 01', { nameOnly: true });
  assert.equal(input.value, '');
  assert.equal(input.getAttribute('placeholder'), 'e.g. Anna K.');
});

test('#422: Save with an untouched empty field still asks for a name', async () => {
  let patched = false;
  const { card } = await renderNameStepFor('tab qa 01');
  globalThis.fetch = async () => {
    patched = true;
    return { ok: true, json: async () => ({}) };
  };
  card.querySelector('FORM').submit();
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(patched, false, 'nothing saved');
  assert.equal(card.querySelector('.pager'), null, 'still on the name step');
  assert.match(card.querySelector('.error').textContent, /Enter a name/);
});

for (const real of ['Ada Lovelace', 'Ada', 'Анна К.']) {
  test(`#422 guard: a chosen name "${real}" stays prefilled`, async () => {
    const { input } = await renderNameStepFor(real);
    assert.equal(input.value, real);
  });
}


// #522 (ichorid review of #538): the pager added no history entries, so the
// browser Back button on step 2 or 3 left the flow instead of going back one
// step. A fake session history: `back()` past the first entry "leaves".
function installFakeHistory() {
  const listeners = new Set();
  const h = {
    entries: [{ state: null }],
    index: 0,
    left: false,
    get state() {
      return this.entries[this.index].state;
    },
    pushState(state) {
      this.entries.splice(this.index + 1);
      this.entries.push({ state: structuredClone(state) });
      this.index += 1;
    },
    replaceState(state) {
      this.entries[this.index] = { state: structuredClone(state) };
    },
    go(delta) {
      const to = this.index + delta;
      if (to < 0) {
        this.left = true;
        return;
      }
      if (to >= this.entries.length) return;
      this.index = to;
      // Browsers fire popstate asynchronously.
      const state = this.state;
      setTimeout(() => {
        for (const fn of listeners) fn({ state });
      }, 0);
    },
    back() {
      this.go(-1);
    },
    forward() {
      this.go(1);
    },
  };
  globalThis.history = h;
  globalThis.addEventListener = (type, fn) => {
    if (type === 'popstate') listeners.add(fn);
  };
  globalThis.removeEventListener = (type, fn) => {
    if (type === 'popstate') listeners.delete(fn);
  };
  h.listeners = listeners;
  return h;
}

function removeFakeHistory() {
  delete globalThis.history;
  delete globalThis.addEventListener;
  delete globalThis.removeEventListener;
}

const tick = () => new Promise((r) => setTimeout(r, 0));

async function renderPagerWithHistory(t, history = installFakeHistory()) {
  installDomFake();
  globalThis.window = globalThis;
  t.after(removeFakeHistory);
  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'Ada' },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage: fakeStorage({ tentura_post_signup_name_done: 'U1' }),
  });
  assert.ok(card.querySelector('.pager'), 'pager rendered');
  const step = () => card.querySelector('.pager-progress').textContent;
  const next = card.querySelector('.btn-primary');
  const back = card.querySelector('.pager-back');
  return { card, history, step, next, back };
}

test('#522: browser Back on step 2 returns to step 1, not out of the pager', async (t) => {
  const { card, history, step, next, back } = await renderPagerWithHistory(t);
  assert.equal(step(), 'Step 1 of 3');
  next.click();
  assert.equal(step(), 'Step 2 of 3');

  history.back();
  await tick();
  assert.equal(history.left, false, 'browser Back did not leave the page');
  assert.equal(step(), 'Step 1 of 3');
  assert.equal(back.hidden, true, 'no Back on step 1');
  assert.equal(card.querySelector('#display-name'), null, 'not the name form');
});

test('#522: browser Back and Forward walk the pager steps', async (t) => {
  const { history, step, next } = await renderPagerWithHistory(t);
  next.click();
  next.click();
  assert.equal(step(), 'Step 3 of 3');

  history.back();
  await tick();
  assert.equal(step(), 'Step 2 of 3');
  history.forward();
  await tick();
  assert.equal(step(), 'Step 3 of 3');
  history.back();
  await tick();
  history.back();
  await tick();
  assert.equal(step(), 'Step 1 of 3');
  assert.equal(history.left, false);
});

test('#522: the in-page Back keeps browser history in step', async (t) => {
  const { history, step, next, back } = await renderPagerWithHistory(t);
  next.click();
  next.click();
  back.click();
  await tick();
  assert.equal(step(), 'Step 2 of 3');
  // Browser Back now goes to step 1, not to a stale step 3 entry.
  history.back();
  await tick();
  assert.equal(step(), 'Step 1 of 3');
  assert.equal(history.left, false);
  // From step 1, browser Back leaves the pager as before.
  history.back();
  await tick();
  assert.equal(history.left, true);
});

test('#522: reload on a later step resumes at that step', async (t) => {
  const first = await renderPagerWithHistory(t);
  first.next.click();
  assert.equal(first.step(), 'Step 2 of 3');

  // Reload keeps the session history entry and its state.
  const reloaded = await renderPagerWithHistory(t, first.history);
  assert.equal(reloaded.step(), 'Step 2 of 3');
  first.history.back();
  await tick();
  assert.equal(reloaded.step(), 'Step 1 of 3');
});

// #522 (ichorid review of #695): the popstate listener was dropped only on
// the next pager render, never when onboarding finished.
test('#522: Continue drops the pager popstate listener', async (t) => {
  const { card, history, next } = await renderPagerWithHistory(t);
  assert.equal(history.listeners.size, 1);
  next.click();
  next.click();
  const continueLink = card.querySelectorAll('a')[0];
  assert.equal(continueLink.hidden, false, 'Continue shows on the last page');
  continueLink.click();
  assert.equal(history.listeners.size, 0);
});

test('#522: Skip drops the pager popstate listener', async (t) => {
  globalThis.location = { assign() {} };
  t.after(() => delete globalThis.location);
  const { card, history } = await renderPagerWithHistory(t);
  assert.equal(history.listeners.size, 1);
  card.querySelector('.hint-link').click();
  assert.equal(history.listeners.size, 0);
});

test('#522 guard: a re-render keeps exactly one popstate listener', async (t) => {
  const first = await renderPagerWithHistory(t);
  await renderPagerWithHistory(t, first.history);
  assert.equal(first.history.listeners.size, 1);
});

test('#522 guard: the pager still steps without a history API', async () => {
  installDomFake();
  globalThis.window = globalThis;
  assert.equal(globalThis.history, undefined);
  const { renderPostSignup } = await import('../onboarding.js');
  const card = document.createElement('div');
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName: 'Ada' },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage: fakeStorage({ tentura_post_signup_name_done: 'U1' }),
  });
  const step = () => card.querySelector('.pager-progress').textContent;
  card.querySelector('.btn-primary').click();
  assert.equal(step(), 'Step 2 of 3');
  card.querySelector('.pager-back').click();
  assert.equal(step(), 'Step 1 of 3');
});
