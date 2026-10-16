// U084 (QA round 2): the invite landing told a brand-new person nothing about
// what Tentura is or why the friend sent the link, and its only extra copy
// was "sign in with seed recovery". These tests check the copy the page
// renders (inviteLandingCopy), not the source text of main.js.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  INVITE_ABOUT_SENTENCE,
  ONBOARDING_PAGES,
  RECOVER_SEED_LINK_LABEL,
  inviteLandingCopy,
} from '../onboarding.js';

test('the invite landing says what Tentura is, in one onboarding sentence', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.equal(copy.about, INVITE_ABOUT_SENTENCE);
  assert.ok(ONBOARDING_PAGES[0].body.startsWith(copy.about));
  assert.equal(copy.about.match(/[.!?](\s|$)/g)?.length, 1);
});

test('a plain invite explains why the friend sent it, without speaking for them', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.match(copy.why, /Nina wants you in their network/);
  assert.doesNotMatch(copy.why, /trusts you/);
});

// Fails on the base: the why line quoted the inviter and the title again,
// right under the request card that already shows both.
test('a request-scoped invite points at the request card instead of repeating it', () => {
  const copy = inviteLandingCopy({
    inviterName: 'Nina',
    hasRequest: true,
    inApp: false,
  });
  assert.match(copy.why, /Nina wants your help with the request above/);
  assert.doesNotMatch(copy.why, /“/);
});

// Fails on the base: a fourth paragraph (the sign-up line) pushed the email
// field below the fold on a phone.
test('in a normal browser there is no separate sign-up paragraph', () => {
  const browser = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.equal(browser.signUp, null);
});

test('in an in-app browser the person is told to open the link elsewhere', () => {
  const inApp = inviteLandingCopy({ inviterName: 'Nina', inApp: true });
  assert.match(inApp.signUp, /browser/);
  assert.doesNotMatch(inApp.signUp, /seed|Google/i);
});

test('the recovery link says what it is for', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.equal(copy.recoverLink, RECOVER_SEED_LINK_LABEL);
  assert.match(copy.recoverLink, /recovery seed/);
});
