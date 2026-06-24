import test from 'node:test';
import assert from 'node:assert/strict';

const VISIT_KEY = 'tentura_visit_id';

function installBrowserGlobals() {
  const storage = new Map();
  globalThis.sessionStorage = {
    getItem: (k) => storage.get(k) ?? null,
    setItem: (k, v) => storage.set(k, v),
    removeItem: (k) => storage.delete(k),
  };
  globalThis.window = globalThis;
  globalThis.location = { origin: 'https://dev.tentura.io' };
  globalThis.TENTURA = { sentryDsn: '' };
  globalThis.Sentry = undefined;
  return storage;
}

test('initVisit creates stable visit_id without Sentry', async () => {
  installBrowserGlobals();
  const { initVisit, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  const first = initVisit({ env: { tier: '1', inApp: false }, hasCode: true });
  const second = initVisit({ env: { tier: '1', inApp: false }, hasCode: true });
  assert.equal(first, second);
  assert.match(first, /^V[0-9a-f]+$/);
});

test('setAccount clears visit_id from sessionStorage', async () => {
  const storage = installBrowserGlobals();
  const { initVisit, setAccount, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  initVisit({ env: {}, hasCode: false });
  assert.ok(storage.has(VISIT_KEY));
  setAccount('Uabc123456789012345678901234567890');
  assert.equal(storage.has(VISIT_KEY), false);
});

test('newAttemptId uses method prefix', async () => {
  installBrowserGlobals();
  const { newAttemptId, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  assert.match(newAttemptId('google'), /^G[0-9a-f]+$/);
  assert.match(newAttemptId('seed'), /^S[0-9a-f]+$/);
});

test('track is no-op when Sentry is absent', async () => {
  installBrowserGlobals();
  const { track, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  assert.equal(track('landing_view'), undefined);
});

test('trackError is no-op when Sentry is absent', async () => {
  installBrowserGlobals();
  const { trackError, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  assert.equal(trackError('preview_error', new Error('x')), undefined);
});

test('initAnalytics wires Sentry when DSN present', async () => {
  installBrowserGlobals();
  globalThis.TENTURA = {
    sentryDsn: 'https://example.com/1',
    sentryEnvironment: 'dev',
    sentryRelease: 'landing@1.0.0',
    apiBase: '',
  };
  const messages = [];
  globalThis.Sentry = {
    browserTracingIntegration: () => ({}),
    replayIntegration: () => ({}),
    init: (opts) => {
      globalThis.__sentryInit = opts;
    },
    getCurrentScope: () => ({
      setTag: () => {},
    }),
    addBreadcrumb: () => {},
    captureMessage: (m) => messages.push(m),
    captureException: () => {},
    setUser: () => {},
  };
  const { initAnalytics, track, resetAnalyticsForTests } = await import('../analytics.js');
  resetAnalyticsForTests();
  initAnalytics();
  track('landing_view');
  assert.equal(messages.length, 1);
  assert.equal(messages[0], 'funnel:landing_view');
  assert.equal(globalThis.__sentryInit.sendDefaultPii, false);
  assert.equal(globalThis.__sentryInit.tracesSampleRate, 1.0);
});
