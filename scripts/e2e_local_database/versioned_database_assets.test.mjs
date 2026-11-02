import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { before, after, test } from 'node:test';
import { chromium } from 'playwright';

const webDir = process.env.LOCAL_DATABASE_WEB_DIR;
assert.ok(webDir, 'Use run_versioned_assets_test.sh to build the production database fixture');
const databaseFiles = ['drift_worker.js', 'sqlite3.wasm'];
let server;
let browser;
let origin;
let prefix;
let requests = [];

before(async () => {
  const manifest = JSON.parse(await readFile(resolve(webDir, 'wasm-preload-manifest.json'), 'utf8'));
  prefix = `/app-assets/${manifest.version}/`;
  // Fail setup clearly if the test did not run the real versioned pipeline.
  for (const file of databaseFiles) {
    assert.ok((await readFile(resolve(webDir, `.${prefix}assets/packages/${file}`))).length > 0);
  }
  server = createServer(async (request, response) => {
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
    const path = new URL(request.url, 'http://localhost').pathname;
    requests.push(`${origin}${request.url}`);
    if (path === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><html><head><base href="/"></head><body>' +
        '<script src="flutter_bootstrap.js" async></script></body></html>');
      return;
    }
    if (path === '/version.json') {
      // The root can advance while an older cached bootstrap is still running.
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify({ version: '999.0.0-newer-deployment' }));
      return;
    }
    const file = resolve(webDir, `.${path}`);
    if (!file.startsWith(`${resolve(webDir)}/`)) {
      response.writeHead(403).end();
      return;
    }
    const types = { '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json' };
    response.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream');
    try {
      response.end(await readFile(file));
    } catch {
      response.writeHead(404).end();
    }
  });
  await new Promise((ready) => server.listen(0, '127.0.0.1', ready));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
});

after(async () => {
  await browser?.close();
  if (server) await new Promise((done) => server.close(done));
});

for (const leftovers of [false, true]) {
  test(`database opens using running-build worker and wasm URLs ${leftovers ? 'with stale root files' : 'on a clean deployment'}`,
    { timeout: 120000 }, async (t) => {
      const rootDatabase = resolve(webDir, 'assets/packages');
      await rm(rootDatabase, { recursive: true, force: true });
      if (leftovers) {
        await mkdir(rootDatabase, { recursive: true });
        for (const file of databaseFiles) {
          const current = await readFile(resolve(webDir, `.${prefix}assets/packages/${file}`));
          let marker;
          if (file.endsWith('.wasm')) {
            // A valid Wasm custom section makes this a distinct older-build
            // fixture without corrupting SQLite or masking URL selection.
            const name = Buffer.from('tentura-stale-root-deployment');
            marker = Buffer.concat([Buffer.from([0, name.length + 1, name.length]), name]);
          } else {
            marker = Buffer.from('\n/* stale root worker from an earlier deployment */\n');
          }
          const stale = Buffer.concat([current, marker]);
          const rootFile = resolve(rootDatabase, file);
          await writeFile(rootFile, stale);
          assert.notDeepEqual(await readFile(rootFile), current,
            'The root leftover must be a distinct file, not a versioned URL alias');
          const served = await fetch(`${origin}/assets/packages/${file}`);
          assert.equal(served.status, 200);
          assert.deepEqual(Buffer.from(await served.arrayBuffer()), stale,
            'Root requests must receive the actual stale copy');
        }
      } else {
        for (const file of databaseFiles) {
          await assert.rejects(readFile(resolve(rootDatabase, file)), { code: 'ENOENT' });
        }
      }
      // Discard fixture-verification fetches: only production opener traffic
      // is evidence for the URL assertions below.
      requests = [];
      const context = await browser.newContext({ serviceWorkers: 'block' });
      t.after(() => context.close());
      const page = await context.newPage();
      const pageErrors = [];
      page.on('pageerror', (error) => pageErrors.push(String(error)));
      page.on('console', (message) => {
        if (message.type() === 'error') pageErrors.push(message.text());
      });
      page.on('requestfailed', (request) => pageErrors.push(`${request.url()}: ${request.failure()?.errorText}`));
      await page.goto(origin);
      try {
        await page.waitForFunction(() => typeof window.localDatabaseCall === 'function', null, { timeout: 20000 });
      } catch (error) {
        throw new Error(`Database fixture did not boot: ${pageErrors.join('\n')}\nRequests: ${JSON.stringify(requests)}`, { cause: error });
      }
      assert.equal(await page.evaluate(() => crossOriginIsolated), true);
      assert.ok(requests.some((url) => new URL(url).pathname === `${prefix}main.dart.wasm`),
        'The fixture must boot the actual versioned Wasm application');

      const opened = await page.evaluate(async () => {
        let timer;
        try {
          return await Promise.race([
            window.localDatabaseCall(JSON.stringify({ operation: 'open' })).then(JSON.parse),
            new Promise((done) => { timer = setTimeout(() => done({ ok: false, error: 'database open timed out' }), 20000); }),
          ]);
        } finally {
          clearTimeout(timer);
        }
      });
      const dbRequests = requests.filter((url) => databaseFiles.some((file) => new URL(url).pathname.endsWith(`/${file}`)));
      t.diagnostic(`Database request URLs: ${JSON.stringify(dbRequests)}`);
      assert.deepEqual(dbRequests.filter((url) => !new URL(url).pathname.startsWith(prefix)), [],
        `Database assets must use ${prefix}; open=${JSON.stringify(opened)}; pageErrors=${pageErrors.join('\n')}`);
      for (const file of databaseFiles) {
        assert.ok(dbRequests.some((url) => new URL(url).pathname === `${prefix}assets/packages/${file}`),
          `The production opener must request ${file} from its running build`);
      }
      assert.equal(opened.ok, true, JSON.stringify(opened));
      const seeded = await page.evaluate(async () => JSON.parse(await window.localDatabaseCall(JSON.stringify({ operation: 'seed' }))));
      assert.equal(seeded.ok, true, JSON.stringify(seeded));
      assert.equal(seeded.value.length, 2);
      const snapshot = await page.evaluate(async () => JSON.parse(await window.localDatabaseCall(JSON.stringify({ operation: 'snapshot' }))));
      assert.equal(snapshot.ok, true, JSON.stringify(snapshot));
      assert.equal(snapshot.value.accounts.length, 2);
      assert.equal(snapshot.value.locale, 'ru');
      await page.evaluate(() => window.localDatabaseCall(JSON.stringify({ operation: 'close' })));
    });
}
