import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const html = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', 'index.html'),
  'utf8',
);

test('landing install chrome points at the cache-busted app icon and PWA manifest', () => {
  assert.match(html, /rel="apple-touch-icon"/);
  assert.match(html, /href="\/tentura-icon-192\.png"/);
  assert.match(html, /rel="manifest"/);
  assert.match(html, /href="\/manifest\.json"/);
  assert.match(html, /name="apple-mobile-web-app-title"/);
});
