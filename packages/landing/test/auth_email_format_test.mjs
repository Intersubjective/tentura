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
