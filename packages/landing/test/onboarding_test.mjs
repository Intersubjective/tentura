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

test('pager Back stays visible on first slide and returns to name step', () => {
  // Page 0 Back must not be hidden — it returns to the name step.
  assert.doesNotMatch(onboardingJs, /back\.hidden\s*=\s*page\s*===\s*0/);
  assert.match(onboardingJs, /onBackFromFirstPage/);
  assert.match(onboardingJs, /onboarding_back/);
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

test('save name then Back from page 1 restores saved prefill', async () => {
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
  assert.equal(input.value, 'agent 3c4703tb');
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
  assert.equal(back.hidden, false);
  back.click();

  const revisited = card.querySelector('#display-name');
  assert.ok(revisited, 'name step re-rendered');
  assert.equal(revisited.value, 'Ada Lovelace');
  assert.equal(
    card.querySelectorAll('.hint-link').length,
    0,
    'Skip for now hidden on revisit',
  );
  assert.ok(events.some((e) => e.name === 'onboarding_back'));
});
