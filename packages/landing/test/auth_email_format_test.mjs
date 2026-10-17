// SPDX-License-Identifier: AGPL-3.0-only
import test from 'node:test';
import assert from 'node:assert/strict';

test('startEmailMagicLink rejects a malformed address without calling the server', async () => {
  globalThis.window = globalThis;
  globalThis.TENTURA = { apiBase: '' };
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return { ok: true, json: async () => ({ ok: true, attemptId: 'E1' }) };
  };
  const { startEmailMagicLink, EmailLinkError } = await import('../auth.js');
  for (const email of ['nope', 'a@b', 'a b@example.com', '@example.com']) {
    await assert.rejects(
      startEmailMagicLink({ email }),
      (e) => e instanceof EmailLinkError && /valid email/.test(e.message),
      email,
    );
  }
  assert.equal(calls, 0);
});

test('isValidEmailFormat accepts what the server accepts', async () => {
  const { isValidEmailFormat } = await import('../auth.js');
  for (const email of ['a@example.com', 'tab-qa-01@test.tentura.local', 'x.y+z@sub.example.org']) {
    assert.equal(isValidEmailFormat(email), true, email);
  }
  for (const email of ['nope', 'a@b', 'a@b.c', 'A@EXAMPLE.COM']) {
    assert.equal(isValidEmailFormat(email), false, email);
  }
});

test('EMAIL_PATTERN is the server kAuthEmailPattern, byte for byte', async () => {
  const { readFile } = await import('node:fs/promises');
  const { EMAIL_PATTERN } = await import('../auth.js');
  const dart = await readFile(
    new URL('../../server/lib/domain/util/email_auth_util.dart', import.meta.url),
    'utf8',
  );
  const m = dart.match(/kAuthEmailPattern\s*=\s*(?:RegExp\()?\s*r'([^']+)'/);
  assert.ok(m, 'kAuthEmailPattern literal not found in email_auth_util.dart');
  assert.equal(EMAIL_PATTERN.source, m[1]);
});

test('a server 400 invalid_email becomes the inline format message', async () => {
  globalThis.window = globalThis;
  globalThis.TENTURA = globalThis.TENTURA ?? { apiBase: '' };
  globalThis.fetch = async () =>
    new Response(JSON.stringify({ ok: false, error: 'invalid_email' }), { status: 400 });
  const { startEmailMagicLink } = await import('../auth.js');
  await assert.rejects(
    startEmailMagicLink({ email: 'a@example.com' }),
    (err) =>
      err.name === 'EmailLinkError' &&
      err.userInput === true &&
      err.message === 'Please enter a valid email address.',
  );
});
