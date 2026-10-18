// #418 (B073): a cancelled or failed Google sign-in came back to the start
// page with no message, so it looked as if nothing had happened. The server
// now appends `?auth_error=google_cancelled|google_failed`; the start page
// turns that flag into one short line (authErrorMessage) above the buttons.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { authErrorMessage } from '../onboarding.js';

test('a cancelled Google sign-in says it was cancelled', () => {
  const msg = authErrorMessage('?auth_error=google_cancelled');
  assert.equal(typeof msg, 'string');
  assert.match(msg, /Google sign-in was cancelled/);
  assert.doesNotMatch(msg, /failed/i);
});

test('a failed Google sign-in says it failed and to try again', () => {
  const msg = authErrorMessage('?auth_error=google_failed');
  assert.equal(typeof msg, 'string');
  assert.match(msg, /Google sign-in failed/);
  assert.match(msg, /try again/i);
});

test('the flag is read among other query params', () => {
  assert.match(
    authErrorMessage('?auth_attempt_id=G123&auth_error=google_cancelled'),
    /cancelled/,
  );
});

test('no flag, an empty search or an unknown value shows nothing', () => {
  assert.equal(authErrorMessage(''), null);
  assert.equal(authErrorMessage(undefined), null);
  assert.equal(authErrorMessage('?signed_in=1'), null);
  assert.equal(authErrorMessage('?auth_error='), null);
  // Never echo an attacker-chosen value onto the page.
  assert.equal(authErrorMessage('?auth_error=%3Cb%3Ehi%3C%2Fb%3E'), null);
  assert.equal(authErrorMessage('?error=access_denied'), null);
});

// Wiring: the signed-out start page (renderNoInvite) must actually show it.
test('the start page renders the auth error from the current URL', () => {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const mainSrc = readFileSync(join(root, 'main.js'), 'utf8');
  assert.match(mainSrc, /\bauthErrorMessage\b[^;]*from '\.\/onboarding\.js'/s);
  const body = mainSrc.slice(mainSrc.indexOf('function renderNoInvite'));
  const fnEnd = body.indexOf('\n}\n');
  assert.match(body.slice(0, fnEnd), /authErrorMessage\(location\.search\)/);
});
