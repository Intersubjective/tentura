import test from 'node:test';
import assert from 'node:assert/strict';
import { shouldPreloadAppAssets } from '../app_preload.js';

test('shouldPreloadAppAssets proceeds in Tier-1 system browser', () => {
  assert.equal(shouldPreloadAppAssets({ env: { inApp: false }, connection: null }), true);
});

test('shouldPreloadAppAssets skips in-app webview', () => {
  assert.equal(shouldPreloadAppAssets({ env: { inApp: true }, connection: null }), false);
});

test('shouldPreloadAppAssets skips Save-Data', () => {
  assert.equal(
    shouldPreloadAppAssets({ env: {}, connection: { saveData: true } }),
    false,
  );
});

test('shouldPreloadAppAssets skips slow-2g and 2g', () => {
  assert.equal(
    shouldPreloadAppAssets({ env: {}, connection: { effectiveType: 'slow-2g' } }),
    false,
  );
  assert.equal(
    shouldPreloadAppAssets({ env: {}, connection: { effectiveType: '2g' } }),
    false,
  );
});

test('shouldPreloadAppAssets proceeds on 3g and missing connection', () => {
  assert.equal(
    shouldPreloadAppAssets({ env: {}, connection: { effectiveType: '3g' } }),
    true,
  );
  assert.equal(shouldPreloadAppAssets({ env: {}, connection: null }), true);
});
