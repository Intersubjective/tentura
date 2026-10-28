import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

async function loadInstall() {
  const { installBfcacheRefresh } = await import('../bfcache.js');
  return installBfcacheRefresh;
}

function fakeWindow() {
  const listeners = new Map();
  return {
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    dispatch(type, event = {}) {
      for (const fn of listeners.get(type) ?? []) fn({ type, ...event });
    },
  };
}

test('a pageshow restored from the back/forward cache runs onRestore once', async () => {
  const installBfcacheRefresh = await loadInstall();
  const win = fakeWindow();
  let calls = 0;
  installBfcacheRefresh(win, () => {
    calls += 1;
  });
  win.dispatch('pageshow', { persisted: true });
  assert.equal(calls, 1);
});

test('a pageshow from a fresh load never runs onRestore', async () => {
  const installBfcacheRefresh = await loadInstall();
  const win = fakeWindow();
  let calls = 0;
  installBfcacheRefresh(win, () => {
    calls += 1;
  });
  win.dispatch('pageshow', { persisted: false });
  assert.equal(calls, 0);
});

test('a pageshow without a persisted flag never runs onRestore', async () => {
  const installBfcacheRefresh = await loadInstall();
  const win = fakeWindow();
  let calls = 0;
  installBfcacheRefresh(win, () => {
    calls += 1;
  });
  win.dispatch('pageshow', {});
  assert.equal(calls, 0);
});

test('every later restore runs onRestore again, fresh loads in between do not', async () => {
  const installBfcacheRefresh = await loadInstall();
  const win = fakeWindow();
  let calls = 0;
  installBfcacheRefresh(win, () => {
    calls += 1;
  });
  win.dispatch('pageshow', { persisted: true });
  win.dispatch('pageshow', { persisted: false });
  win.dispatch('pageshow', { persisted: true });
  assert.equal(calls, 2);
});

test('events other than pageshow do not run onRestore', async () => {
  const installBfcacheRefresh = await loadInstall();
  const win = fakeWindow();
  let calls = 0;
  installBfcacheRefresh(win, () => {
    calls += 1;
  });
  win.dispatch('pagehide', { persisted: true });
  win.dispatch('visibilitychange', { persisted: true });
  assert.equal(calls, 0);
});

test('main.js installs the back/forward-cache refresh handler at boot', () => {
  const raw = readFileSync(join(root, 'main.js'), 'utf8');
  // Comments must not satisfy the check: blank them, keeping offsets.
  const mainSrc = raw
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, (m) => ' '.repeat(m.length));
  assert.match(
    mainSrc,
    /import\s*\{[^}]*\binstallBfcacheRefresh\b[^}]*\}\s*from\s*['"]\.\/bfcache\.js['"]/,
  );

  const call = /installBfcacheRefresh\(\s*window\s*,/.exec(mainSrc);
  assert.ok(call, 'installBfcacheRefresh(window, ...) is called');

  // Boot-time means it runs without waiting for anything: either a
  // top-level statement ahead of the main() invocation, or the opening
  // statements of main() before its first await.
  const lineStart = mainSrc.lastIndexOf('\n', call.index) + 1;
  const topLevel = lineStart === call.index;
  const bootCall = mainSrc.indexOf('\nmain();');
  assert.ok(bootCall > 0, 'main() is invoked at load');

  const mainFn = mainSrc.indexOf('async function main() {');
  const firstAwait = mainSrc.indexOf('await ', mainFn);
  const atStartOfMain =
    mainFn >= 0 && call.index > mainFn && call.index < firstAwait;

  assert.ok(
    (topLevel && call.index < bootCall) || atStartOfMain,
    'installBfcacheRefresh runs at page load (top level before main(), or at the start of main() before any await)',
  );
});
