// Actual document reload -> production cookie parser/repository -> AuthCubit
// -> rendered current account -> trusted click on the real saved-account tile.
// Run only this file through run_with_test_cleanup.sh (it builds its fixture).
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { before, after, test } from 'node:test';
import { chromium } from 'playwright';
import { WebSocketServer } from 'ws';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const alice = 'account-alice';
const boris = 'account-boris';
const cookieName = '__Host-tentura_session';
const socketConnections = new Set();
const replies = [];
let server, sockets, browser, origin, webDir;
let documents = 0;

before(async () => {
  webDir = await mkdtemp(join(tmpdir(), 'tentura-cookie-sign-in-reload-'));
  server = createServer(async (request, response) => {
    const path = new URL(request.url, 'http://localhost').pathname;
    const subject = request.headers.cookie?.split('; ')
      .find((value) => value.startsWith(`${cookieName}=`))?.slice(cookieName.length + 1);
    const json = (body) => {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(body));
    };
    if (path.startsWith('/session/')) {
      const owner = path.slice('/session/'.length);
      assert.equal(request.method, 'POST');
      assert.ok([alice, boris].includes(owner));
      response.setHeader('Set-Cookie', `${cookieName}=${owner}; Path=/; HttpOnly; Secure; SameSite=Lax`);
      json({ ok: true });
    } else if (path === '/api/v2/session/access-token') {
      assert.equal(request.method, 'POST');
      assert.ok([alice, boris].includes(subject), 'Use the real HttpOnly browser cookie');
      const body = { subject, access_token: `token-${subject}`, expires_in: 3600 };
      replies.push({ document: documents, body });
      json(body);
    } else if (path === '/api/v2/session/logout') {
      response.setHeader('Set-Cookie', `${cookieName}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`);
      json({ ok: true });
    } else if (path === '/cookie') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><title>Cookie owner</title>');
    } else if (path === '/' || path === '/app') {
      documents++;
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><html><head><base href="/"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><script src="flutter_bootstrap.js" async></script></body></html>');
    } else {
      const file = resolve(webDir, `.${path}`);
      if (!file.startsWith(`${resolve(webDir)}/`)) {
        response.writeHead(403).end();
        return;
      }
      response.setHeader('Content-Type', {
        '.wasm': 'application/wasm', '.js': 'text/javascript',
        '.mjs': 'text/javascript', '.json': 'application/json',
      }[extname(path)] || 'application/octet-stream');
      try { response.end(await readFile(file)); }
      catch { response.writeHead(404).end(); }
    }
  });
  sockets = new WebSocketServer({ server, path: '/api/v2/ws' });
  sockets.on('connection', (socket) => {
    socketConnections.add(socket);
    socket.on('message', (raw) => {
      const frame = JSON.parse(raw.toString());
      if (frame.type === 'auth') {
        socket.send(JSON.stringify({ type: 'auth', intent: frame.intent, result: 'success' }));
      }
      if (frame.type === 'ping') socket.send(JSON.stringify({ type: 'pong' }));
    });
    socket.on('close', () => socketConnections.delete(socket));
  });
  await new Promise((ready) => server.listen(0, '127.0.0.1', ready));
  origin = `http://127.0.0.1:${server.address().port}`;

  // FLUTTER_ROOT uses the already-cached tool snapshot so this same test also
  // runs in an Alloy filesystem sandbox where the shared SDK is read-only.
  const sdk = process.env.FLUTTER_ROOT;
  const command = sdk ? join(sdk, 'bin/cache/dart-sdk/bin/dart') : 'flutter';
  const args = sdk
    ? [join(sdk, 'bin/cache/flutter_tools.snapshot'), '--no-version-check', '--suppress-analytics']
    : [];
  args.push(
    'build', 'web', '--wasm', '--no-pub', '--no-web-resources-cdn',
    '--target=integration_test/support/cookie_sign_in_reload_browser_app.dart',
    `--output=${webDir}`, `--dart-define=SERVER_NAME=${origin}`,
    `--dart-define=WS_SERVER_NAME=${origin}`,
  );
  await new Promise((done, reject) => {
    const build = spawn(command, args, {
      cwd: join(root, 'packages/client'), stdio: 'inherit',
      env: {
        ...process.env, FLUTTER_ALREADY_LOCKED: 'true',
        FLUTTER_SUPPRESS_ANALYTICS: 'true', DASH__SUPPRESS_ANALYTICS: 'true',
      },
    });
    build.on('error', reject);
    build.on('exit', (code) => code === 0 ? done() : reject(new Error(`Flutter build exited ${code}`)));
  });
  browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
}, { timeout: 600000 });

after(async () => {
  await browser?.close();
  for (const socket of socketConnections) socket.terminate();
  sockets?.close();
  if (server) await new Promise((done) => server.close(done));
  if (webDir) await rm(webDir, { recursive: true, force: true });
});

test('a document reload restores the cookie owner and selecting a stale saved account cannot replace that identity', { timeout: 60000 }, async (t) => {
  const context = await browser.newContext({ viewport: { width: 375, height: 667 } });
  t.after(() => context.close());
  const otherTab = await context.newPage();
  await otherTab.goto(`${origin}/cookie`);
  const setCookie = (owner) => otherTab.evaluate(async (owner) =>
    (await fetch(`/session/${owner}`, { method: 'POST', credentials: 'include' })).ok, owner);
  assert.equal(await setCookie(alice), true);
  assert.equal((await context.cookies()).find((cookie) => cookie.name === cookieName).httpOnly, true);
  assert.equal(await otherTab.evaluate(() => document.cookie.includes('__Host-tentura_session')), false);

  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (error) => errors.push(String(error)));
  await page.goto(`${origin}/app`);
  await waitForAccount(page, alice);
  const firstDocument = await page.evaluate(() => performance.timeOrigin);
  assert.equal((await state(page)).storedAccount, alice);
  assert.equal(documents, 1);

  // Change only the server's cookie. The stored account is still Alice until
  // the real browser reload reruns production startup against Boris's cookie.
  assert.equal(await setCookie(boris), true);
  assert.equal((await state(page)).storedAccount, alice);
  await page.reload();
  await waitForAccount(page, boris);
  assert.ok(await page.evaluate(() => performance.timeOrigin) > firstDocument, 'Reload must create a new document');
  assert.equal(documents, 2);
  const restored = await state(page);
  assert.equal(restored.document, 2, 'Flutter main must run again');
  assert.equal(restored.storedAccount, boris);
  assert.deepEqual(restored.parsedSubjects, [boris]);
  assert.equal(replies.at(-1).document, 2);
  assert.equal(replies.at(-1).body.subject, boris);
  assert.equal(replies.at(-1).body.access_token, `token-${boris}`);
  await page.getByText(`Current account: ${boris}`, { exact: true }).waitFor({ state: 'visible' });
  t.diagnostic('A new document restored and rendered Boris from its HTTP response, replacing the persisted Alice account');

  // A trusted browser click enters the actual AccountListTile -> AuthCubit
  // path. It may neither undo the cookie-authoritative restoration nor leave
  // Boris authenticated while pretending that Alice signed in.
  const parsedBeforeTap = restored.parsedSubjects.length;
  await page.locator('[flt-semantics-identifier="select-saved-alice"]').click();
  await page.waitForFunction((before) => {
    const value = JSON.parse(window.cookieSignInState());
    return value.parsedSubjects.length > before && !value.isLoading;
  }, parsedBeforeTap);
  const rejected = await state(page);
  assert.equal(replies.at(-1).body.subject, boris);
  assert.equal(rejected.parsedSubjects.at(-1), boris);
  assert.notEqual(rejected.account, alice, 'Selecting Alice after reloading Boris must never mark Alice current');
  assert.equal(rejected.published.includes(alice), false, 'Never publish Alice even transiently');
  assert.equal(rejected.hasValidToken, false, 'Undo the leftover cookie authentication');
  assert.equal(rejected.isSessionAuth, false);
  assert.equal(rejected.boundAccount, null);
  await page.getByText('Sign in again as Alice', { exact: false }).waitFor({ state: 'visible' });
  assert.deepEqual(errors, []);
  assert.equal(await page.evaluate(() => sessionStorage.getItem('cookieSignIn.flutterError')), null);
});

async function state(page) {
  return page.evaluate(() => JSON.parse(window.cookieSignInState()));
}

async function waitForAccount(page, account) {
  await page.waitForFunction((account) => {
    if (typeof window.cookieSignInState !== 'function') return false;
    const value = JSON.parse(window.cookieSignInState());
    return value.account === account && value.boundAccount === account && !value.isLoading;
  }, account, { timeout: 30000 });
}
