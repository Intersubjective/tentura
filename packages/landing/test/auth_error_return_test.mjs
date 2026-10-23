// #418 (B073): a cancelled or failed Google sign-in came back to the start
// page with no message, so it looked as if nothing had happened. The server
// now appends `?auth_error=google_cancelled|google_failed`; the start page
// turns that flag into one short line (authErrorMessage) above the buttons.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { authErrorMessage, urlWithoutAuthError } from '../onboarding.js';

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

// #601: the banner showed again on every reload because `?auth_error=` stayed
// in the address bar. After rendering, the page rewrites its own URL without
// the flag (history.replaceState), keeping everything else.
test('the address without auth_error keeps the path, other params and hash', () => {
  assert.equal(
    urlWithoutAuthError({
      pathname: '/invite/ABC123',
      search: '?auth_error=google_failed',
      hash: '',
    }),
    '/invite/ABC123',
  );
  assert.equal(
    urlWithoutAuthError({
      pathname: '/',
      search: '?auth_attempt_id=G123&auth_error=google_cancelled',
      hash: '#top',
    }),
    '/?auth_attempt_id=G123#top',
  );
  // An empty or unknown value is still a flag to drop.
  assert.equal(
    urlWithoutAuthError({ pathname: '/', search: '?auth_error=' }),
    '/',
  );
});

test('an address without auth_error is left alone', () => {
  assert.equal(urlWithoutAuthError({ pathname: '/', search: '' }), null);
  assert.equal(
    urlWithoutAuthError({ pathname: '/invite/ABC123', search: '?signed_in=1' }),
    null,
  );
  assert.equal(urlWithoutAuthError(), null);
});

// Wiring (browser-only, so read from source): main() clears the flag after
// both the start page and the invite page have rendered, and the invite page
// (renderAnonymous) shows the same banner as the start page.
test('main clears auth_error from the URL after rendering', () => {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const mainSrc = readFileSync(join(root, 'main.js'), 'utf8');
  assert.match(mainSrc, /\burlWithoutAuthError\b[^;]*from '\.\/onboarding\.js'/s);
  const clearFn = mainSrc.slice(mainSrc.indexOf('function clearAuthErrorFromUrl'));
  assert.match(
    clearFn.slice(0, clearFn.indexOf('\n}\n')),
    /urlWithoutAuthError\(location\)[\s\S]*history\.replaceState\(/,
  );
  const mainFn = mainSrc.slice(mainSrc.indexOf('async function main'));
  assert.match(mainFn, /renderNoInvite\(\);\s*clearAuthErrorFromUrl\(\);/);
  assert.match(
    mainFn,
    /render\(preview\);[\s\S]*renderError\(\);\s*\}\s*clearAuthErrorFromUrl\(\);/,
  );
});

test('the invite page shows the auth error after a failed sign-in', () => {
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const mainSrc = readFileSync(join(root, 'main.js'), 'utf8');
  const body = mainSrc.slice(mainSrc.indexOf('function renderAnonymous'));
  const fnEnd = body.indexOf('\n}\n');
  assert.match(body.slice(0, fnEnd), /authErrorMessage\(location\.search\)/);
  assert.match(body.slice(0, fnEnd), /role: 'alert'/);
});
