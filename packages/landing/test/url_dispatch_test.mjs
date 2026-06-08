import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const mainJs = readFileSync(join(root, 'main.js'), 'utf8');

test('existing-user CTA targets hash accept-invite route', () => {
  assert.match(mainJs, /function openAcceptInviteUrl\(code\)/);
  assert.match(mainJs, /appHashUrl\(`\/accept-invite\/\$\{encodeURIComponent\(code\)\}`\)/);
  assert.match(mainJs, /ctaOpenAcceptInvite/);
});

test('anonymous render does not offer generic open-app CTA', () => {
  const anonymousBlock = mainJs.slice(
    mainJs.indexOf('function renderAnonymous'),
    mainJs.indexOf('function render(p)'),
  );
  assert.doesNotMatch(anonymousBlock, /ctaOpenApp\('Open the app'\)/);
});

test('Google CTA uses full same-origin returnTo for invite', () => {
  assert.match(mainJs, /function googleReturnTo\(inviteCode\)/);
  assert.match(
    mainJs,
    /url\.searchParams\.set\('returnTo', returnTo\)/,
  );
});

test('renderNoInvite has email sign-in and invite entry', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('function addAppPreconnect'),
  );
  assert.match(block, /setState\('no-invite'\)/);
  assert.match(block, /renderEmailMagicLinkForm/);
  assert.match(block, /renderInviteEntryForm/);
  assert.doesNotMatch(block, /cta_open_app_no_invite/);
  assert.doesNotMatch(block, /Open Tentura/);
});

test('renderNoInvite includes Tier-2 browser escape', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('function addAppPreconnect'),
  );
  assert.match(block, /ctaOpenInBrowser/);
});

test('Google CTA hidden in in-app browser via env.inApp guard', () => {
  assert.match(mainJs, /if \(!GOOGLE_ENABLED \|\| env\.inApp\) return null/);
});

test('already-friends uses completion copy after signed-in return', () => {
  assert.match(mainJs, /function isSignedInReturn\(\)/);
  const block = mainJs.slice(
    mainJs.indexOf('function renderAlreadyFriends'),
    mainJs.indexOf('function renderExistingUser'),
  );
  assert.match(block, /isSignedInReturn\(\)/);
  assert.match(block, /You’re all set/);
  assert.match(block, /Your account is ready, and \$\{name\} is connected with you/);
  assert.match(block, /You’re connected with \$\{name\}/);
  assert.doesNotMatch(block, /already connected/i);
});
