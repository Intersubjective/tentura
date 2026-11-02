import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const landing = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = resolve(landing, '../..');

test('landing HTML and CSS do not depend on root Flutter assets', () => {
  const offenders = [];
  function inspect(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory() && entry.name !== 'test') inspect(path);
      if (entry.isFile() && /\.(css|html)$/.test(entry.name) &&
          /["'(]\s*\/assets\//.test(readFileSync(path, 'utf8'))) {
        offenders.push(relative(landing, path));
      }
    }
  }
  inspect(landing);
  assert.deepEqual(offenders, [], 'Root Flutter assets disappear when deployment prunes stale files');
});

for (const environment of ['dev', 'prod']) {
  test(`${environment} landing archive includes all four Inter fonts at CSS-relative URLs`, () => {
    const workflow = readFileSync(join(root, '.github/workflows',
      environment === 'dev' ? 'pipeline.yml' : 'pipeline-prod.yml'), 'utf8');
    // Match the existing static, dependency-free tar manifest convention.
    const manifest = workflow.match(/-C packages\/landing\s*\\\s*\n\s*([^\n]+)/);
    assert.ok(manifest, 'The workflow must package the static landing');
    const packaged = manifest[1].trim().split(/\s+/);
    const css = readFileSync(join(landing, 'styles.css'), 'utf8');
    const faces = [...css.matchAll(/@font-face\s*\{([^}]+)\}/g)]
      .filter((match) => /font-family:\s*['"]Inter['"]/.test(match[1]));
    assert.equal(faces.length, 4, 'Inter regular, medium, semibold and bold must remain available');
    assert.deepEqual(faces.map((face) => Number(face[1].match(/font-weight:\s*(\d+)/)?.[1])).sort(),
      [400, 500, 600, 700]);
    for (const face of faces) {
      const url = face[1].match(/url\(['"]?([^'"\s)]+)/)?.[1];
      assert.ok(url, 'Each font face needs a URL');
      assert.ok(!url.startsWith('/') && !/^[a-z]+:/i.test(url),
        `${url} must resolve relative to the landing stylesheet`);
      const path = relative(landing, resolve(landing, url)).replaceAll('\\', '/');
      assert.ok(!path.startsWith('..') && existsSync(join(landing, path)),
        `${url} must be a font shipped inside packages/landing`);
      assert.ok(packaged.some((item) => item === path ||
        path.startsWith(`${item.replace(/\/$/, '')}/`)),
        `${path} must be included in the ${environment} landing tarball`);
    }
  });
}
