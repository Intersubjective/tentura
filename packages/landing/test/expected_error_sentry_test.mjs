// #762 / #788: an expected 4xx validation failure on the landing (a display
// name the server rejects with 400, a QA test login on a domain the server
// refuses with 400) is shown to the person but must not open a Sentry issue. The
// funnel breadcrumb stays; captureException is skipped. Unexpected failures
// (other 4xx such as 403/404/429, 5xx, network) still reach Sentry.
import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.window = globalThis;
globalThis.TENTURA = {
  sentryDsn: 'https://example.com/1',
  sentryEnvironment: 'dev',
  sentryRelease: 'landing@1.0.0',
  apiBase: '',
};
const storage = new Map();
globalThis.sessionStorage = {
  getItem: (k) => storage.get(k) ?? null,
  setItem: (k, v) => storage.set(k, v),
  removeItem: (k) => storage.delete(k),
};

const exceptions = [];
const breadcrumbs = [];
globalThis.Sentry = {
  browserTracingIntegration: () => ({}),
  replayIntegration: () => ({}),
  init: () => {},
  getCurrentScope: () => ({ setTag: () => {} }),
  addBreadcrumb: (b) => breadcrumbs.push(b),
  captureMessage: () => {},
  captureException: (err) => exceptions.push(err),
  setUser: () => {},
};

const { initAnalytics, trackError, resetAnalyticsForTests } = await import(
  '../analytics.js'
);
const { saveDisplayName } = await import('../onboarding.js');
const { startTestLogin } = await import('../auth.js');

function reset() {
  exceptions.length = 0;
  breadcrumbs.length = 0;
  resetAnalyticsForTests();
  initAnalytics();
}

function respond(status, body = {}) {
  globalThis.fetch = async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

async function rejection(promise) {
  try {
    await promise;
  } catch (err) {
    return err;
  }
  assert.fail('expected a rejection');
}

test('trackError skips captureException for an error marked expected', () => {
  reset();
  const err = new Error('shown to the person');
  err.expected = true;
  trackError('some_error', err);
  assert.equal(exceptions.length, 0);
  assert.equal(breadcrumbs.length, 1);
  assert.equal(breadcrumbs[0].message, 'some_error');
  trackError('some_error', new Error('a fault'));
  assert.equal(exceptions.length, 1);
});

// #762
test('a 400 from the display-name save shows the message without a Sentry issue', async () => {
  reset();
  respond(400, { error: 'displayName must be 3..32 chars' });
  const err = await rejection(saveDisplayName('x'));
  assert.equal(
    err.message,
    'That name could not be saved. Use 3 to 32 characters and try again.',
  );
  trackError('signup_name_error', err);
  assert.equal(exceptions.length, 0);
  assert.equal(breadcrumbs.length, 1);
  assert.equal(breadcrumbs[0].message, 'signup_name_error');
});

test('a 5xx from the display-name save is still a Sentry issue', async () => {
  reset();
  respond(500);
  const err = await rejection(saveDisplayName('Valid name'));
  assert.equal(err.message, 'Could not save your name. Try again.');
  trackError('signup_name_error', err);
  assert.equal(exceptions.length, 1);
});

test('a network failure on the display-name save is still a Sentry issue', async () => {
  reset();
  globalThis.fetch = async () => {
    throw new TypeError('Failed to fetch');
  };
  const err = await rejection(saveDisplayName('Valid name'));
  trackError('signup_name_error', err);
  assert.equal(exceptions.length, 1);
});

// #788: only 400 (refused QA domain or malformed address) is the expected
// answer. 404 means QA_SIMPLE_LOGIN_MODE is off on a server whose landing
// shows the button (config mismatch), 403/429/other 4xx are faults too.
test('a 400 from QA test login shows the message without a Sentry issue', async () => {
  reset();
  respond(400, { error: 'domain_not_allowed' });
  const err = await rejection(startTestLogin({ email: 'u@example.com' }));
  assert.equal(err.name, 'EmailLinkError');
  assert.equal(
    err.message,
    'Test login failed. Check the email domain and try again.',
  );
  trackError('qa_test_login_error', err);
  assert.equal(exceptions.length, 0);
  assert.equal(breadcrumbs.length, 1);
  assert.equal(breadcrumbs[0].message, 'qa_test_login_error');
});

for (const status of [403, 404, 429, 503]) {
  test(`a ${status} from QA test login is still a Sentry issue`, async () => {
    reset();
    respond(status);
    const err = await rejection(startTestLogin({ email: 'u@test.tentura.local' }));
    assert.equal(err.name, 'EmailLinkError');
    trackError('qa_test_login_error', err);
    assert.equal(exceptions.length, 1);
  });
}

test('a network failure on QA test login is still a Sentry issue', async () => {
  reset();
  globalThis.fetch = async () => {
    throw new TypeError('Failed to fetch');
  };
  const err = await rejection(startTestLogin({ email: 'u@test.tentura.local' }));
  trackError('qa_test_login_error', err);
  assert.equal(exceptions.length, 1);
});
