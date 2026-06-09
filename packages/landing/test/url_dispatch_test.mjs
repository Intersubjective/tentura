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

test('anonymous render reveals login options behind existing-account CTA', () => {
  const anonymousBlock = mainJs.slice(
    mainJs.indexOf('function renderAnonymous'),
    mainJs.indexOf('function render(p)'),
  );
  assert.match(anonymousBlock, /createSignInReveal\(code\)/);
  assert.doesNotMatch(anonymousBlock, /renderEmailMagicLinkForm\(\)/);
  assert.doesNotMatch(anonymousBlock, /ctaGoogleSignIn\(code\)/);
});

test('Google CTA uses full same-origin returnTo for invite', () => {
  assert.match(mainJs, /function googleReturnTo\(inviteCode\)/);
  assert.match(
    mainJs,
    /url\.searchParams\.set\('returnTo', returnTo\)/,
  );
});

test('renderNoInvite has sign-in reveal and invite entry', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('async function main'),
  );
  assert.match(block, /setState\('no-invite'\)/);
  assert.match(block, /createSignInReveal\(''\)/);
  assert.match(block, /renderInviteEntryForm/);
  assert.doesNotMatch(block, /cta_open_app_no_invite/);
  assert.doesNotMatch(block, /Open Tentura/);
});

test('login options include Google on Tier 1 and browser escape on Tier 2', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function buildLoginOptionItems'),
    mainJs.indexOf('function createSignInReveal'),
  );
  assert.match(block, /renderEmailMagicLinkForm/);
  assert.match(block, /if \(env\.inApp\)/);
  assert.match(block, /ctaOpenInBrowser/);
  assert.match(block, /ctaGoogleSignIn\(inviteCode\)/);
});

test('Tier 1 login options include recover-from-seed CTA', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function buildLoginOptionItems'),
    mainJs.indexOf('function createSignInReveal'),
  );
  assert.match(block, /Recover from seed/);
  assert.match(block, /cta_recover_seed/);
  assert.match(block, /appRecoverUrl\(\)/);
  const tier1Branch = block.slice(block.indexOf('} else {'));
  assert.doesNotMatch(tier1Branch, /ctaOpenInBrowser/);
});

test('appRecoverUrl uses non-root WASM bootstrap path with hash route', () => {
  assert.match(mainJs, /function appRecoverUrl\(\)/);
  assert.match(mainJs, /new URL\('\/recover', location\.origin\)/);
  assert.match(mainJs, /url\.hash = '\/recover-seed'/);
});

test('existing-account reveal mounts tier-specific login options', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function createSignInReveal'),
    mainJs.indexOf('function googleReturnTo'),
  );
  assert.match(block, /buildLoginOptionItems\(inviteCode\)/);
  assert.match(block, /I already have an account/);
  assert.match(block, /aria-controls/);
});

test('email sign-in field avoids login/password autofill heuristics', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderEmailMagicLinkForm'),
    mainJs.indexOf('function renderInviteEntryForm'),
  );
  assert.match(block, /name: 'identifier'/);
  assert.match(block, /autocomplete: 'section-signin email'/);
  assert.doesNotMatch(block, /name: 'email'/);
});

test('invite entry field is scoped away from sign-in autofill', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderInviteEntryForm'),
    mainJs.indexOf('function isSignedInReturn'),
  );
  assert.match(block, /autocomplete: 'section-invite off'/);
  assert.match(block, /name: 'invite-code'/);
});

test('renderNoInvite uses shared sign-in reveal helper', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('async function main'),
  );
  assert.match(block, /createSignInReveal\(''\)/);
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

test('main starts app preload before invite preview fetch', () => {
  const preloadIdx = mainJs.indexOf('startAppPreload(');
  const previewIdx = mainJs.indexOf('fetchPreview(');
  assert.ok(preloadIdx >= 0, 'startAppPreload call missing');
  assert.ok(previewIdx >= 0, 'fetchPreview call missing');
  assert.ok(preloadIdx < previewIdx, 'preload must start before preview fetch');
  assert.doesNotMatch(mainJs, /await startAppPreload/);
});

test('main uses location.origin for app CTAs', () => {
  assert.match(mainJs, /`\$\{location\.origin\}\/#\$\{normalized\}`/);
  assert.match(mainJs, /`\$\{location\.origin\}\/`/);
  assert.doesNotMatch(mainJs, /APP_BASE|resolveAppBase|addAppPreconnect/);
});
