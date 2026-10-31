// Real Chrome, real production opener and real repositories. No backend is
// needed: this tests the persistent local database, not remote authentication.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { before, after } from 'node:test';
import { chromium } from 'playwright';

const webDir = process.env.LOCAL_DATABASE_WEB_DIR;
assert.ok(webDir, 'Use run.sh to compile the test entry point with --wasm');
let server;
export let browser;
let origin;

before(async () => {
  server = createServer(async (request, response) => {
    // Match deployment isolation; disabling COOP/COEP would hide the OPFS bug.
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    const path = new URL(request.url, 'http://localhost').pathname;
    if (path === '/') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><html><head><base href="/"></head><body>' +
        '<script src="flutter_bootstrap.js" async></script></body></html>');
      return;
    }
    const file = resolve(webDir, `.${path}`);
    if (!file.startsWith(`${resolve(webDir)}/`)) {
      response.writeHead(403).end();
      return;
    }
    const types = { '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json' };
    const suffix = Object.keys(types).find((extension) => path.endsWith(extension));
    response.setHeader('Content-Type', types[suffix] || 'application/octet-stream');
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

export async function pageIn(context) {
  const page = await context.newPage();
  const errors = [];
  let wasmLoaded = false;
  page.on('pageerror', (error) => errors.push(String(error)));
  page.on('response', (response) => {
    if (new URL(response.url()).pathname === '/main.dart.wasm' && response.ok()) wasmLoaded = true;
  });
  await page.goto(origin);
  try {
    await page.waitForFunction(() => typeof window.localDatabaseCall === 'function', null, { timeout: 60000 });
  } catch (error) {
    throw new Error(`Test application did not boot: ${errors.join('\n')}`, { cause: error });
  }
  assert.equal(wasmLoaded, true, 'The browser must execute the --wasm build');
  assert.equal(await page.evaluate(() => crossOriginIsolated), true);
  return page;
}

export async function response(page, operation, values = {}) {
  // OPFS contention can return SQLITE_IOERR in one tab and leave the other's
  // transaction waiting forever. Keep running the fifteen rounds and report
  // both symptoms rather than hanging the entire test file.
  const timeoutMs = ['contacts', 'settingsAndAccounts', 'roundState'].includes(operation) ? 5000 : 15000;
  let timer;
  try {
    return await Promise.race([
      page.evaluate(async (request) => JSON.parse(await window.localDatabaseCall(JSON.stringify(request))), { operation, ...values }),
      new Promise((done) => {
        timer = setTimeout(() => done({ ok: false, error: `${operation} did not finish within ${timeoutMs} ms` }), timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

export async function call(page, operation, values = {}) {
  const result = await response(page, operation, values);
  assert.equal(result.ok, true, `${operation} must succeed: ${result.error || ''}\n${result.stack || ''}`);
  return result.value;
}

export function hasDatabase(inventory, api) {
  return inventory.existing.some((entry) => entry.api === api && entry.name === 'main_db');
}

export function assertModeTelemetry(telemetry, mode) {
  const modePattern = /\b(sharedIndexedDb|unsafeIndexedDb|opfsLocks|opfsShared|inMemory)\b/g;
  // Observe what the production opener reports, not the probe's list of
  // available implementations. A report of another storage mode also fails.
  for (const [channel, entries] of [
    ['log', telemetry.logs],
    ['breadcrumb', telemetry.breadcrumbs.map((crumb) => JSON.stringify(crumb))],
  ]) {
    const reports = entries.map((entry) => [...new Set([...entry.matchAll(modePattern)].map((match) => match[1]))]).filter((modes) => modes.length > 0);
    assert.deepEqual(reports, [[mode]], `The production opener must report ${mode} in exactly one ${channel} per session`);
  }
}

export async function seedLegacy(context) {
  const page = await pageIn(context);
  await call(page, 'legacy');
  const fixture = await call(page, 'seed');
  const snapshot = await call(page, 'snapshot');
  const inventory = await call(page, 'inventory');
  assert.equal(hasDatabase(inventory, 'opfs'), true, 'Fixture must be a real OPFS profile');
  assert.equal(hasDatabase(inventory, 'indexedDb'), false, 'Fixture must have no IndexedDB copy');
  await call(page, 'close');
  await page.close();
  return { fixture, snapshot };
}

