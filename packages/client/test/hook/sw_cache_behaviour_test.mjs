// Behavioural check of the generated app-cache service worker
// (hook/build/wasm_preload_artifacts.dart -> tentura-app-cache-sw.js).
//
// Runs the worker source in a vm sandbox with fake self/caches/fetch and
// asserts a broken CacheStorage never breaks a fetch (issue #622).
//
//   node --test packages/client/test/hook/sw_cache_behaviour_test.mjs
//
// SW_FILE=<path> tests an already generated tentura-app-cache-sw.js (the Dart
// test in wasm_preload_artifacts_test.dart does this); otherwise the worker
// template is read from the generator source.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ORIGIN = 'https://dev.tentura.io';
const ASSET = '/main.dart.wasm';

function workerSource() {
  if (process.env.SW_FILE) return readFileSync(process.env.SW_FILE, 'utf8');
  const generator = join(
    dirname(fileURLToPath(import.meta.url)),
    '../../hook/build/wasm_preload_artifacts.dart',
  );
  const dart = readFileSync(generator, 'utf8');
  const start = dart.indexOf("'''", dart.indexOf('String _serviceWorkerSource('));
  assert.ok(start > 0, 'service worker template not found');
  const bodyStart = dart.indexOf('\n', start) + 1;
  const body = dart.slice(bodyStart, dart.indexOf("''';", bodyStart));
  const filled = body
    .replaceAll('$version', 'test-version')
    .replaceAll('$assetPathsJson', JSON.stringify([ASSET]));
  // Only the two interpolations above are understood here.
  assert.ok(!filled.includes('$'), 'unexpected Dart interpolation in template');
  assert.ok(!filled.includes('\\'), 'unexpected Dart escape in template');
  return filled;
}

/// The cache name the loaded worker considers current (its own version).
function currentCacheName() {
  const m = workerSource().match(/const CACHE_VERSION = '([^']*)';/);
  assert.ok(m, 'CACHE_VERSION not found in worker source');
  return 'tentura-app-assets-' + m[1];
}

class FakeResponse {
  constructor(body, { ok = true, status = 200 } = {}) {
    this.body = body;
    this.ok = ok;
    this.status = status;
  }
  clone() {
    return new FakeResponse(this.body, { ok: this.ok, status: this.status });
  }
}

/// Loads the worker with [cacheImpl] behaviour; returns hooks to drive it.
function loadWorker({
  open = async (name, mk) => mk(name),
  keys = async () => [],
  del = async () => true,
  fetchImpl = async () => new FakeResponse('network'),
  cache = {},
} = {}) {
  const listeners = {};
  const store = new Map();
  const calls = { fetch: 0, put: [], deleted: [], claim: 0, skipWaiting: 0 };
  function makeCache() {
    return {
      match: cache.match ?? (async (req) => store.get(req.url)),
      put:
        cache.put ??
        (async (req, res) => {
          calls.put.push(req.url);
          store.set(req.url, res);
        }),
    };
  }
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (type, fn) => {
      listeners[type] = fn;
    },
    skipWaiting: () => {
      calls.skipWaiting++;
      return Promise.resolve();
    },
    clients: {
      claim: () => {
        calls.claim++;
        return Promise.resolve();
      },
    },
  };
  const context = vm.createContext({
    self,
    caches: {
      open: (name) => open(name, makeCache),
      keys,
      delete: async (k) => {
        calls.deleted.push(k);
        return del(k);
      },
    },
    fetch: async (req) => {
      calls.fetch++;
      return fetchImpl(req);
    },
    URL,
    Promise,
    console,
  });
  vm.runInContext(workerSource(), context);

  async function dispatchFetch(path) {
    const request = { url: ORIGIN + path, method: 'GET' };
    let responded = null;
    const extended = [];
    listeners.fetch({
      request,
      respondWith: (p) => {
        responded = Promise.resolve(p);
      },
      waitUntil: (p) => extended.push(Promise.resolve(p)),
    });
    const result = responded === null ? null : await responded;
    await Promise.all(extended);
    return { responded: responded !== null, result };
  }

  async function dispatchLifecycle(type) {
    const extended = [];
    listeners[type]({ waitUntil: (p) => extended.push(Promise.resolve(p)) });
    await Promise.all(extended);
  }

  return { calls, store, dispatchFetch, dispatchLifecycle };
}

const reject = (msg) => async () => {
  throw new Error(msg);
};

test('cache.put rejecting still serves the network response', async () => {
  const sw = loadWorker({
    cache: { put: reject('Cache.put() encountered a network error') },
  });
  const { responded, result } = await sw.dispatchFetch(ASSET);
  assert.equal(responded, true);
  assert.equal(result.body, 'network');
});

test('cache.put throwing synchronously still serves the network response', async () => {
  const sw = loadWorker({
    cache: {
      put: () => {
        throw new Error('QuotaExceededError');
      },
    },
  });
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.body, 'network');
});

test('caches.open rejecting serves the network response', async () => {
  const sw = loadWorker({ open: reject('SecurityError') });
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.body, 'network');
  assert.equal(sw.calls.fetch, 1);
});

test('cache.match rejecting serves the network response', async () => {
  const sw = loadWorker({ cache: { match: reject('broken cache') } });
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.body, 'network');
});

test('a cached asset is served from the cache without the network', async () => {
  const sw = loadWorker();
  sw.store.set(ORIGIN + ASSET, new FakeResponse('cached'));
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.body, 'cached');
  assert.equal(sw.calls.fetch, 0);
});

test('a successful network response is put into the cache', async () => {
  const sw = loadWorker();
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.body, 'network');
  assert.deepEqual(sw.calls.put, [ORIGIN + ASSET]);
  assert.equal(sw.store.get(ORIGIN + ASSET).body, 'network');
  const second = await sw.dispatchFetch(ASSET);
  assert.equal(second.result.body, 'network');
  assert.equal(sw.calls.fetch, 1, 'second load comes from the cache');
});

test('an error response is returned but not cached', async () => {
  const sw = loadWorker({
    fetchImpl: async () => new FakeResponse('nope', { ok: false, status: 503 }),
  });
  const { result } = await sw.dispatchFetch(ASSET);
  assert.equal(result.status, 503);
  assert.deepEqual(sw.calls.put, []);
});

test('requests outside the app shell are left to the browser', async () => {
  const sw = loadWorker();
  const { responded } = await sw.dispatchFetch('/api/v2/graphql');
  assert.equal(responded, false);
});

test('install takes over from an old worker at once', async () => {
  const sw = loadWorker();
  await sw.dispatchLifecycle('install');
  assert.equal(sw.calls.skipWaiting, 1);
});

test('activate claims clients and drops old app caches', async () => {
  const sw = loadWorker({
    keys: async () => ['tentura-app-assets-old', currentCacheName(), 'other'],
  });
  await sw.dispatchLifecycle('activate');
  assert.equal(sw.calls.claim, 1);
  assert.deepEqual(sw.calls.deleted, ['tentura-app-assets-old']);
});

test('activate still claims clients when CacheStorage is broken', async () => {
  const sw = loadWorker({ keys: reject('SecurityError') });
  await sw.dispatchLifecycle('activate');
  assert.equal(sw.calls.claim, 1);
});

test('activate still claims clients when deleting an old cache fails', async () => {
  const sw = loadWorker({
    keys: async () => ['tentura-app-assets-old'],
    del: reject('broken cache'),
  });
  await sw.dispatchLifecycle('activate');
  assert.equal(sw.calls.claim, 1);
});
