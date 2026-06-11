// Guards against the "deployed landing misses a module" failure mode: the CI
// tar in .github/workflows/pipeline.yml enumerates landing files explicitly,
// and a module missing from that list resolves to the SPA-fallback HTML in
// production — the import fails with a MIME error and the landing hangs on
// the loading spinner (the exact bug this test was added for: onboarding.js).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const landingRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = join(landingRoot, '..', '..');
const pipeline = readFileSync(
  join(repoRoot, '.github', 'workflows', 'pipeline.yml'),
  'utf8',
);

// The tar file list: the line following `-C packages/landing \` (shell
// line continuation).
const tarListMatch = pipeline.match(/-C packages\/landing\s*\\\s*\n\s*([^\n]+)/);
assert.ok(tarListMatch, 'pipeline.yml packages the landing with -C packages/landing');
const packaged = new Set(tarListMatch[1].trim().split(/\s+/));

/** Recursively collect relative ES-module imports starting from main.js. */
function collectModules(entry, seen = new Set()) {
  if (seen.has(entry)) return seen;
  seen.add(entry);
  const src = readFileSync(join(landingRoot, entry), 'utf8');
  for (const m of src.matchAll(/from\s+'\.\/([^']+)'/g)) {
    collectModules(m[1], seen);
  }
  return seen;
}

test('every module reachable from main.js is in the CI tar list', () => {
  const required = collectModules('main.js');
  required.add('index.html');
  required.add('styles.css');
  required.add('config.js');
  for (const file of required) {
    assert.ok(
      packaged.has(file),
      `${file} is imported/required by the landing but missing from the ` +
        'pipeline.yml tar list — it would 404 to SPA HTML in production',
    );
  }
});

test('index.html script sources are in the CI tar list', () => {
  const html = readFileSync(join(landingRoot, 'index.html'), 'utf8');
  for (const m of html.matchAll(/src="\.?\/?([a-z_./]+\.js)"/g)) {
    const file = m[1];
    if (file.startsWith('http')) continue;
    // config.local.js is optional-by-design (404 tolerated via type=module+onerror or absence)
    assert.ok(
      packaged.has(file),
      `${file} is loaded by index.html but missing from the pipeline.yml tar list`,
    );
  }
});
