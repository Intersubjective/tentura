import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = readFileSync(join(root, 'app_preload.js'), 'utf8');

test('app_preload registers SW and uses manifest', () => {
  assert.match(src, /navigator\.serviceWorker\.register\(SW_URL\)/);
  assert.match(src, /\/wasm-preload-manifest\.json/);
  assert.match(src, /tentura-app-assets-/);
});

test('app_preload uses cache storage and low-priority idle scheduling', () => {
  assert.match(src, /caches\.open/);
  assert.match(src, /priority: 'low'/);
  assert.match(src, /requestIdleCallback/);
});

test('app_preload limits concurrency and swallows errors', () => {
  assert.match(src, /MAX_CONCURRENT/);
  assert.match(src, /catch/);
});
