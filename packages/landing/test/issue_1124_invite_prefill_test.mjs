// #1124: invalid / failed invite preview keeps the code in the entry field;
// legacy hash invite URLs redirect to /invite/:code.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  renderLanding,
  landingReplaceTo,
} from './landing_browser_fake.mjs';

const INVALID_PREVIEW = {
  codeStatus: 'invalid',
  callerStatus: 'anonymous',
  suggestedAction: 'invalid',
};

test('invalid preview keeps BADCODE123 in the invite entry field (EN)', async () => {
  const card = await renderLanding(
    {
      pathname: '/invite/BADCODE123',
      preview: INVALID_PREVIEW,
    },
    '1124-invalid-en',
  );
  const input = card.querySelector('#invite-entry');
  assert.equal(input?.value, 'BADCODE123');
  assert.match(card.textContent, /no longer valid/i);
  assert.match(card.textContent, /find this invite/i);
});

test('invalid preview keeps trailing dash in the invite entry field (EN)', async () => {
  const card = await renderLanding(
    {
      pathname: '/invite/IQAFX0000000-',
      preview: INVALID_PREVIEW,
    },
    '1124-dash-en',
  );
  const input = card.querySelector('#invite-entry');
  assert.equal(input?.value, 'IQAFX0000000-');
  assert.match(card.textContent, /ends with a hyphen/i);
});

test('failed preview request still prefills the invite code (EN)', async () => {
  const card = await renderLanding(
    {
      pathname: '/invite/BADCODE123',
      previewFails: true,
    },
    '1124-preview-fail-en',
  );
  const input = card.querySelector('#invite-entry');
  assert.equal(input?.value, 'BADCODE123');
  assert.match(card.textContent, /Something went wrong/i);
});

test('invalid preview shows Russian copy when ?lang=ru', async () => {
  const card = await renderLanding(
    {
      pathname: '/invite/BADCODE123',
      search: '?lang=ru',
      preview: INVALID_PREVIEW,
    },
    '1124-invalid-ru',
  );
  assert.equal(card.querySelector('#invite-entry')?.value, 'BADCODE123');
  assert.match(card.textContent, /больше не действует/);
  assert.match(card.textContent, /не нашли это приглашение/i);
});

test('/ with #/invite/ redirects to /invite/ preserving ?lang=ru', async () => {
  const card = await renderLanding(
    {
      pathname: '/',
      search: '?lang=ru',
      hash: '#/invite/BADCODE123',
    },
    '1124-hash-invite',
    { expectContent: false },
  );
  const url = landingReplaceTo(card);
  assert.ok(url, 'expected location.replace');
  const parsed = new URL(url, 'https://tentura.test');
  assert.equal(parsed.pathname, '/invite/BADCODE123');
  assert.equal(parsed.searchParams.get('lang'), 'ru');
});

for (const [hash, code] of [
  ['#/accept-invite/Iabc456', 'Iabc456'],
  ['#/sign/up/Iabc789', 'Iabc789'],
]) {
  test(`/ with ${hash} redirects to /invite/${code}`, async () => {
    const card = await renderLanding(
      { pathname: '/', hash },
      `1124-hash-${code}`,
      { expectContent: false },
    );
    const url = landingReplaceTo(card);
    assert.ok(url);
    assert.equal(new URL(url, 'https://tentura.test').pathname, `/invite/${code}`);
  });
}
