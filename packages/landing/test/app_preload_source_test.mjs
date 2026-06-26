import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const preloadSrc = readFileSync(join(root, 'app_preload.js'), 'utf8');
const compatSrc = readFileSync(join(root, 'browser_compatibility.js'), 'utf8');

test('app_preload registers SW and uses manifest', () => {
  assert.match(preloadSrc, /navigator\.serviceWorker\.register\(SW_URL\)/);
  assert.match(preloadSrc, /\/wasm-preload-manifest\.json/);
  assert.match(preloadSrc, /tentura-app-assets-/);
});

test('app_preload uses path-specific warmUrlsFromManifest', () => {
  assert.match(preloadSrc, /warmUrlsFromManifest/);
  assert.match(preloadSrc, /browser_compatibility\.js/);
  assert.doesNotMatch(preloadSrc, /manifest\.mainWasm/);
  assert.doesNotMatch(preloadSrc, /manifest\.preload/);
});

test('app_preload uses cache storage and low-priority idle scheduling', () => {
  assert.match(preloadSrc, /caches\.open/);
  assert.match(preloadSrc, /priority: 'low'/);
  assert.match(preloadSrc, /requestIdleCallback/);
});

test('app_preload limits concurrency and swallows errors', () => {
  assert.match(preloadSrc, /MAX_CONCURRENT/);
  assert.match(preloadSrc, /catch/);
});

test('browser_compatibility exports prefersWasmApp and warmUrlsFromManifest', () => {
  assert.match(compatSrc, /export function prefersWasmApp/);
  assert.match(compatSrc, /export function warmUrlsFromManifest/);
  assert.match(compatSrc, /DEFAULT_WASM_ALLOW/);
});
