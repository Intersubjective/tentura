// U084 (QA round 2): the invite landing told a brand-new person nothing about
// what Tentura is or why the friend sent the link, and its only extra copy
// was "sign in with seed recovery".
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  ONBOARDING_PAGES,
  RECOVER_SEED_LINK_LABEL,
  inviteLandingCopy,
} from '../onboarding.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const mainJs = readFileSync(join(root, 'main.js'), 'utf8');

test('the invite landing says what Tentura is, in the onboarding words', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.equal(copy.about, ONBOARDING_PAGES[0].body);
  assert.match(copy.about, /ask for help/);
});

test('a plain invite explains why the friend sent it', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.match(copy.why, /Nina/);
  assert.match(copy.why, /trust/);
});

test('a request-scoped invite names the request', () => {
  const copy = inviteLandingCopy({
    inviterName: 'Nina',
    beaconTitle: 'Move a couch on Saturday',
    inApp: false,
  });
  assert.match(copy.why, /Nina/);
  assert.match(copy.why, /“Move a couch on Saturday”/);
});

test('the sign-up line no longer leads with seed recovery', () => {
  const browser = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.doesNotMatch(browser.signUp, /seed/i);
  assert.match(browser.signUp, /email or Google/);
  assert.match(browser.signUp, /Already have an account/);
  const inApp = inviteLandingCopy({ inviterName: 'Nina', inApp: true });
  assert.doesNotMatch(inApp.signUp, /Google/);
  assert.match(inApp.signUp, /browser/);
});

test('the recovery link says what it is for', () => {
  const copy = inviteLandingCopy({ inviterName: 'Nina', inApp: false });
  assert.match(copy.recoverLink, /recovery seed/);
  assert.equal(copy.recoverLink, RECOVER_SEED_LINK_LABEL);
  assert.match(mainJs, /RECOVER_SEED_LINK_LABEL,?\n\s*\);/);
  assert.doesNotMatch(mainJs, /'Recover from seed'/);
});

test('the anonymous invite page renders the explanation', () => {
  assert.match(mainJs, /inviteLandingCopy\(/);
  const anon = mainJs.slice(mainJs.indexOf('function renderAnonymous('));
  const body = anon.slice(0, anon.indexOf('\n}\n'));
  assert.match(body, /copy\.about/);
  assert.match(body, /copy\.why/);
  assert.match(body, /copy\.signUp/);
  assert.doesNotMatch(body, /seed recovery/);
});
