import test from 'node:test';
import assert from 'node:assert/strict';

test('startEmailMagicLink returns attemptId from JSON', async () => {
  globalThis.window = globalThis;
  globalThis.TENTURA = { apiBase: '' };
  globalThis.fetch = async () => ({
    ok: true,
    json: async () => ({ ok: true, attemptId: 'Eabc1234567890' }),
  });
  const { startEmailMagicLink } = await import('../auth.js');
  const attemptId = await startEmailMagicLink({
    email: 'a@example.com',
    code: 'Iabc',
  });
  assert.equal(attemptId, 'Eabc1234567890');
});

test('startTestLogin posts to test-login and returns redirectUrl', async () => {
  globalThis.window = globalThis;
  globalThis.TENTURA = { apiBase: '' };
  let capturedUrl;
  let capturedInit;
  globalThis.fetch = async (url, init) => {
    capturedUrl = url;
    capturedInit = init;
    return {
      ok: true,
      json: async () => ({
        ok: true,
        immediate: true,
        redirectUrl: 'https://dev.tentura.io/invite/Iabc?signed_in=1',
        isNewAccount: false,
      }),
    };
  };
  const { startTestLogin } = await import('../auth.js');
  const result = await startTestLogin({
    email: 'u@test.tentura.local',
    code: 'Iabc',
  });
  assert.equal(capturedUrl, '/api/v2/auth/email/test-login');
  assert.equal(capturedInit.method, 'POST');
  assert.equal(
    JSON.parse(capturedInit.body).email,
    'u@test.tentura.local',
  );
  assert.equal(result.redirectUrl, 'https://dev.tentura.io/invite/Iabc?signed_in=1');
  assert.equal(result.isNewAccount, false);
});

test('google start URL carries auth_attempt_id in start and returnTo', async () => {
  const { newAttemptId } = await import('../analytics.js');
  const attemptId = newAttemptId('google');
  const origin = 'https://dev.tentura.io';
  const url = new URL('/api/auth/google/start', origin);
  url.searchParams.set('auth_attempt_id', attemptId);
  const returnUrl = new URL(`${origin}/invite/Iabc`);
  returnUrl.searchParams.set('auth_attempt_id', attemptId);
  url.searchParams.set('returnTo', returnUrl.toString());
  assert.equal(url.searchParams.get('auth_attempt_id'), attemptId);
  const nested = new URL(url.searchParams.get('returnTo'));
  assert.equal(nested.searchParams.get('auth_attempt_id'), attemptId);
});

test('seed recover URL carries auth_attempt_id', async () => {
  const { newAttemptId } = await import('../analytics.js');
  const attemptId = newAttemptId('seed');
  const url = new URL('/recover', 'https://dev.tentura.io');
  url.hash = '/recover-seed';
  url.searchParams.set('auth_attempt_id', attemptId);
  url.searchParams.set('invite', 'Iabc');
  assert.equal(url.searchParams.get('auth_attempt_id'), attemptId);
  assert.equal(url.hash, '#/recover-seed');
});

test('newAttemptId uses google and seed prefixes', async () => {
  const { newAttemptId } = await import('../analytics.js');
  assert.match(newAttemptId('google'), /^G[0-9a-f]+$/);
  assert.match(newAttemptId('seed'), /^S[0-9a-f]+$/);
});
