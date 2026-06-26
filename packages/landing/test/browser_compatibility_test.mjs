import test from 'node:test';
import assert from 'node:assert/strict';
import { warmUrlsFromManifest, dedupeUrls } from '../browser_compatibility.js';

const sampleManifest = {
  version: '1.0.0',
  mainWasm: '/main.dart.wasm',
  mainJs: '/main.dart.js',
  sharedPreload: [
    '/flutter_bootstrap.js?v=1.0.0',
    '/assets/packages/sqlite3.wasm',
  ],
  wasmPreload: ['/main.dart.wasm', '/main.dart.mjs'],
  jsPreload: ['/main.dart.js'],
};

test('warmUrlsFromManifest wasm path excludes main.dart.js', () => {
  const urls = warmUrlsFromManifest(sampleManifest, true);
  assert.ok(urls.includes('/main.dart.wasm'));
  assert.ok(urls.includes('/main.dart.mjs'));
  assert.ok(urls.includes('/flutter_bootstrap.js?v=1.0.0'));
  assert.equal(urls.includes('/main.dart.js'), false);
});

test('warmUrlsFromManifest js path excludes main.dart.wasm', () => {
  const urls = warmUrlsFromManifest(sampleManifest, false);
  assert.ok(urls.includes('/main.dart.js'));
  assert.equal(urls.includes('/main.dart.wasm'), false);
  assert.equal(urls.includes('/main.dart.mjs'), false);
});

test('dedupeUrls preserves order', () => {
  const urls = dedupeUrls(['/a', '/b', '/a', '/c']);
  assert.deepEqual(urls, ['/a', '/b', '/c']);
});
