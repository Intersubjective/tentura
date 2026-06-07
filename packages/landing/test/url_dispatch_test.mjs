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

test('Google CTA includes returnTo invite path', () => {
  assert.match(
    mainJs,
    /searchParams\.set\('returnTo', `\/invite\/\$\{encodeURIComponent\(inviteCode\)\}`\)/,
  );
});
