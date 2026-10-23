// Behavioural check of the service-worker update reload in web/index.html
// (issue #627 / #622): when a new deploy's worker takes control of an open
// tab, the tab reloads once so it never runs old JS against new chunks.
//
// Runs the inline <script id="sw-update-reload"> in a vm sandbox with a fake
// navigator.serviceWorker and window.location.
//
//   node --test packages/client/test/web/sw_update_reload_test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

function reloadScript() {
  const index = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), '../../web/index.html'),
    'utf8',
  );
  const m = index.match(/<script id="sw-update-reload">([\s\S]*?)<\/script>/);
  assert.ok(m, 'script#sw-update-reload not found in web/index.html');
  return m[1];
}

/// Runs the script; [controller] is the worker controlling the page at load.
function load({ controller = null, withServiceWorker = true } = {}) {
  const listeners = {};
  const calls = { reload: 0, registered: [] };
  const navigator = {};
  if (withServiceWorker) {
    navigator.serviceWorker = {
      controller,
      addEventListener: (type, fn) => {
        (listeners[type] ??= []).push(fn);
      },
      register: (url) => {
        calls.registered.push(url);
        return Promise.resolve({});
      },
    };
  }
  const window = { location: { reload: () => calls.reload++ } };
  vm.runInNewContext(reloadScript(), { navigator, window });
  const fire = (type) => (listeners[type] ?? []).forEach((fn) => fn({}));
  return { calls, listeners, fire };
}

test('a new worker taking over an old one reloads the tab once', () => {
  const page = load({ controller: { scriptURL: 'old' } });
  assert.deepEqual(page.calls.registered, ['/tentura-app-cache-sw.js']);
  page.fire('controllerchange');
  assert.equal(page.calls.reload, 1);
  page.fire('controllerchange');
  assert.equal(page.calls.reload, 1, 'reloaded more than once');
});

test('the first install (no previous controller) does not reload', () => {
  const page = load({ controller: null });
  page.fire('controllerchange');
  assert.equal(page.calls.reload, 0);
});

test('no service worker support is a no-op', () => {
  const page = load({ withServiceWorker: false });
  assert.equal(page.calls.reload, 0);
});
