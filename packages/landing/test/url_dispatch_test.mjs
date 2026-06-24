import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const mainJs = readFileSync(join(root, 'main.js'), 'utf8');
const authJs = readFileSync(join(root, 'auth.js'), 'utf8');

test('existing-user CTA targets hash accept-invite route', () => {
  assert.match(mainJs, /function openAcceptInviteUrl\(code\)/);
  assert.match(mainJs, /appHashUrl\(`\/accept-invite\/\$\{encodeURIComponent\(code\)\}`\)/);
  assert.match(mainJs, /ctaOpenAcceptInvite/);
});

test('anonymous render does not offer generic open-app CTA or seed signup', () => {
  const anonymousBlock = mainJs.slice(
    mainJs.indexOf('function renderAnonymous'),
    mainJs.indexOf('function render(p)'),
  );
  assert.doesNotMatch(anonymousBlock, /ctaOpenApp\('Open the app'\)/);
  assert.doesNotMatch(mainJs, /signUpWithSeed/);
  assert.doesNotMatch(mainJs, /renderSignupForm/);
  assert.doesNotMatch(mainJs, /I'm new — sign up/);
});

test('anonymous render surfaces email and Google auth directly', () => {
  const anonymousBlock = mainJs.slice(
    mainJs.indexOf('function renderAnonymous'),
    mainJs.indexOf('function render(p)'),
  );
  assert.match(anonymousBlock, /renderInviteAuthOptions\(code\)/);
  assert.doesNotMatch(anonymousBlock, /createSignInReveal/);
});

test('Google CTA uses full same-origin returnTo for invite', () => {
  assert.match(mainJs, /function googleReturnTo\(inviteCode\)/);
  assert.match(
    mainJs,
    /url\.searchParams\.set\('returnTo', returnUrl\.toString\(\)\)/,
  );
  assert.match(mainJs, /returnUrl\.searchParams\.set\('auth_attempt_id', attemptId\)/);
});

test('renderNoInvite hides auth behind createSignInReveal', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('async function main'),
  );
  assert.match(block, /setState\('no-invite'\)/);
  assert.match(block, /renderInviteEntryForm/);
  assert.match(block, /createSignInReveal\('', \{/);
  assert.match(block, /hideOnReveal: \[inviteIntro, inviteForm\]/);
  assert.doesNotMatch(block, /renderInviteAuthOptions\(''\)/);
  assert.doesNotMatch(block, /cta_open_app_no_invite/);
  assert.doesNotMatch(block, /Open Tentura/);
});

test('createSignInReveal uses buildSignInOptionItems with Sign in label', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function buildSignInOptionItems'),
    mainJs.indexOf('function createSignInReveal'),
  );
  assert.match(block, /'Sign in'/);
  assert.match(block, /renderEmailMagicLinkForm/);
  assert.match(block, /ctaRecoverSeed\(inviteCode\)/);
});

test('createSignInReveal offers invite-mode undo', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function createSignInReveal'),
    mainJs.indexOf('// Email, Google, and seed recovery for invite pages.'),
  );
  assert.match(block, /Have an invite link\?/);
  assert.match(block, /track\('cta_invite_mode'\)/);
  assert.match(block, /for \(const node of hideOnReveal\) node\.hidden = false/);
});

test('renderNoInvite shows Open Tentura when signed_in=1', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderNoInvite'),
    mainJs.indexOf('async function main'),
  );
  assert.match(block, /isSignedInReturn\(\)/);
  assert.match(block, /ctaOpenApp\(\)/);
});

test('invite auth options include email, Google, and recover-from-seed', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderInviteAuthOptions'),
    mainJs.indexOf('function renderEmailMagicLinkForm'),
  );
  assert.match(block, /renderEmailMagicLinkForm/);
  assert.match(block, /if \(env\.inApp\)/);
  assert.match(block, /ctaOpenInBrowser/);
  assert.match(block, /ctaGoogleSignIn\(inviteCode\)/);
  assert.match(block, /ctaRecoverSeed\(inviteCode\)/);
});

test('appRecoverUrl carries invite query and recover-seed hash route', () => {
  assert.match(mainJs, /function appRecoverUrl\(inviteCode\)/);
  assert.match(mainJs, /new URL\('\/recover', location\.origin\)/);
  assert.match(mainJs, /url\.hash = '\/recover-seed'/);
  assert.match(mainJs, /url\.searchParams\.set\('auth_attempt_id', attemptId\)/);
  assert.match(mainJs, /url\.searchParams\.set\('invite', inviteCode\)/);
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

test('email magic link sends inviteCode when present', () => {
  assert.match(authJs, /if \(code\) payload\.inviteCode = code/);
  assert.doesNotMatch(authJs, /signUpWithSeed/);
});

test('invite entry field is scoped away from sign-in autofill', () => {
  const block = mainJs.slice(
    mainJs.indexOf('function renderInviteEntryForm'),
    mainJs.indexOf('function isSignedInReturn'),
  );
  assert.match(block, /autocomplete: 'section-invite off'/);
  assert.match(block, /name: 'invite-code'/);
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
