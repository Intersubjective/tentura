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

test('main.js gates post-signup on new-signup return and falls back', () => {
  assert.match(
    mainJs,
    /isNewSignupReturn\(location\.search\) && !isOnboardingDone\(sessionStorage\)/,
  );
  // 401/no-profile falls through to the normal render (replayed URL safety).
  assert.match(mainJs, /post_signup_fallback/);
  // Post-signup check runs before the no-code branch so `/invite/?new=1` works.
  assert.ok(
    mainJs.indexOf('isNewSignupReturn') < mainJs.indexOf('renderNoInvite()'),
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

test('email success state tells the user to check email and hides submit', () => {
  assert.match(mainJs, /'Check your email'/);
  assert.match(mainJs, /successEl\.hidden = false/);
  assert.match(mainJs, /emailInput\.disabled = true/);
  assert.match(mainJs, /submit\.hidden = true/);
});

test('pager clamps page index and hidden controls actually hide', () => {
  // show() must never step past the last page even if a hidden control fires.
  assert.match(onboardingJs, /Math\.max\(0, Math\.min\(index, ONBOARDING_PAGES\.length - 1\)\)/);
  // `.btn { display: block }` outranks the UA [hidden] rule; the stylesheet
  // must restore it or `next.hidden = true` leaves Next visible on page 3.
  const css = readFileSync(join(root, 'styles.css'), 'utf8');
  assert.match(css, /\[hidden\]\s*\{\s*display:\s*none\s*!important;?\s*\}/);
});
