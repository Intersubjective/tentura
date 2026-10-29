import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { resetAnalyticsForTests } from '../analytics.js';

// Like the other main.js rendering tests, use a minimal DOM: the static
// landing deliberately has no npm dependencies or bundler.
class FakeNode {
  constructor(nodeType = 1) {
    this.nodeType = nodeType;
    this.children = [];
    this.attrs = {};
  }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  addEventListener() {}
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this.children = [...nodes]; }
  get textContent() {
    return this.nodeType === 3
      ? this.data
      : this.children.map((child) => child.textContent).join('');
  }
}

async function waitForLanding(predicate, message) {
  // main() is fire-and-forget. Wait for its visible result, including an
  // error card so failures report the actual page and SDK call counts.
  const deadline = Date.now() + 2000;
  while (!predicate() && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.ok(predicate(), message);
}

test('restoring an invite refreshes the connection card while Sentry and Replay initialise only once', async () => {
  const card = new FakeNode();
  const app = new FakeNode();
  const browser = new EventTarget();
  const storage = new Map();
  const capturedErrors = [];
  let initCalls = 0;
  let replayCalls = 0;
  let previewCalls = 0;
  let connected = false;

  globalThis.window = globalThis;
  globalThis.addEventListener = browser.addEventListener.bind(browser);
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(globalThis, 'navigator', {
    value: {
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130',
      language: 'en-US', languages: ['en-US'],
      connection: { saveData: true },
    },
    configurable: true,
  });
  globalThis.TENTURA = { sentryDsn: 'https://example.com/1' };
  globalThis.Sentry = {
    browserTracingIntegration: () => ({}),
    replayIntegration: () => { replayCalls += 1; return {}; },
    init: () => {
      initCalls += 1;
      // Reproduce the browser SDK's rejection of a second Replay instance.
      if (initCalls > 1) {
        throw new Error('Multiple Sentry Session Replay instances are not supported');
      }
    },
    getCurrentScope: () => ({ setTag() {} }),
    addBreadcrumb() {},
    captureException: (error) => capturedErrors.push(error.message),
    setUser() {},
  };
  globalThis.sessionStorage = {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: (key) => storage.delete(key),
  };
  globalThis.location = {
    pathname: '/invite/Iabc123', search: '', hash: '',
    origin: 'https://tentura.test', href: 'https://tentura.test/invite/Iabc123',
  };
  globalThis.document = {
    title: '', documentElement: {},
    getElementById: (id) => id === 'card' ? card : app,
    createElement: () => new FakeNode(),
    createDocumentFragment: () => new FakeNode(11),
    createTextNode: (text) => Object.assign(new FakeNode(3), { data: String(text) }),
    querySelector: () => null,
    addEventListener() {},
  };
  globalThis.fetch = async (url) => {
    assert.equal(url, '/api/v2/invite/Iabc123/preview');
    previewCalls += 1;
    return {
      ok: true, status: 200,
      json: async () => ({
        codeStatus: 'available',
        callerStatus: connected ? 'authenticated' : 'anonymous',
        suggestedAction: connected ? 'already-friends' : 'accept-as-new',
        inviter: { id: 'U1', displayName: 'Nina' },
      }),
    };
  };

  resetAnalyticsForTests();
  await import('../main.js');
  await waitForLanding(
    () => card.textContent.includes('Nina invited you to Tentura') ||
      card.textContent.includes('Something went wrong'),
    'the first page load renders an invite or error card',
  );
  assert.equal(initCalls, 1, 'the first page load initialises Sentry');
  assert.equal(replayCalls, 1, 'the first page load creates Replay');
  assert.equal(previewCalls, 1);
  assert.match(card.textContent, /Nina invited you to Tentura/);
  assert.deepEqual(capturedErrors, [], 'the initial render succeeds');

  // The cached document survives while signup changes the server session.
  // Back restores the original invite URL without the signed_in query flag.
  connected = true;
  const pageshow = new Event('pageshow');
  Object.defineProperty(pageshow, 'persisted', { value: true });
  browser.dispatchEvent(pageshow);
  await waitForLanding(
    () => card.textContent.includes('You’re connected with Nina') ||
      card.textContent.includes('Something went wrong'),
    'the restored page renders the refreshed connection or error card',
  );

  assert.deepEqual({
    initCalls,
    replayCalls,
    refreshedPreview: previewCalls > 1,
    connectedCard: card.textContent.includes('You’re connected with Nina'),
    errorCard: card.textContent.includes('Something went wrong'),
    capturedErrors,
  }, {
    initCalls: 1,
    replayCalls: 1,
    refreshedPreview: true,
    connectedCard: true,
    errorCard: false,
    capturedErrors: [],
  });
});
