// Real HttpOnly cookies shared by tabs, real browser fetch/WebSocket, and the
// production auth/effect/navigation chain. Never replace location or its port.
// Run: scripts/run_with_test_cleanup.sh --timeout 20m -- bash scripts/e2e_session_account/run.sh
// Coverage: HTTP -> MyWork mapper control + rejection; socket -> real reconnect
// rejection; both -> AuthCubit -> localized snackbar -> one new document -> B.
// Siblings: HTTP/socket x EN/RU x 375x667; cold boot A / other-tab swap / reload B.
// Input, Request state and participant roles are n/a to account authentication.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { resolve, extname } from 'node:path';
import { before, after, test } from 'node:test';
import { chromium } from 'playwright';
import { WebSocketServer } from 'ws';

const webDir = process.env.SESSION_ACCOUNT_WEB_DIR;
assert.ok(webDir, 'Use scripts/e2e_session_account/run.sh');
const cookieName = '__Host-tentura_session';
const tokenA = 'token-account-a';
const tokenB = 'token-account-b';
let server, sockets, browser, origin;
let documents = 0;
let requests = [];
let frames = [];
let connections = [];

before(async () => {
  server = createServer(async (request, response) => {
    const path = new URL(request.url, 'http://localhost').pathname;
    const subject = request.headers.cookie?.split('; ').find((c) => c.startsWith(`${cookieName}=`))?.split('=')[1];
    const body = await Array.fromAsync(request).then((chunks) => Buffer.concat(chunks).toString());
    requests.push({ document: documents, path, headers: request.headers, body, subject });
    const json = (value) => {
      response.setHeader('Content-Type', 'application/json');
      response.end(JSON.stringify(value));
    };
    if (path.startsWith('/session/')) {
      const account = path.slice('/session/'.length);
      assert.ok(['account-a', 'account-b'].includes(account));
      response.setHeader('Set-Cookie', `${cookieName}=${account}; Path=/; HttpOnly; Secure; SameSite=Lax`);
      json({ ok: true });
    } else if (path === '/api/v2/session/access-token') {
      assert.ok(['account-a', 'account-b'].includes(subject), 'The browser must send its real HttpOnly cookie');
      json({ subject, access_token: `token-${subject}`, expires_in: 0 });
    } else if (path.endsWith('/graphql')) {
      assert.equal(JSON.parse(body).operationName, 'MyWorkInit');
      json({ data: {
        __typename: 'query_root', authoredNonArchived: [], helpOfferedNonArchived: [], obligationBeacons: [],
        archivedIdHints: [{ __typename: 'beacon_archived', beacon_id: 'archived-control' }],
      } });
    } else if (path === '/cookie') {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><title>Other tab</title>');
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
        '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
      }[extname(path)] || 'application/octet-stream');
      try { response.end(await readFile(file)); }
      catch { response.writeHead(404).end(); }
    }
  });
  sockets = new WebSocketServer({ server, path: '/api/v2/ws' });
  sockets.on('connection', (socket) => {
    const document = documents;
    connections.push({ document, socket });
    socket.on('message', (raw) => {
      const frame = JSON.parse(raw.toString());
      frames.push({ document, frame });
      if (frame.type === 'auth') socket.send(JSON.stringify({ type: 'auth', intent: frame.intent, result: 'success' }));
      if (frame.type === 'ping') socket.send(JSON.stringify({ type: 'pong' }));
    });
  });
  await new Promise((ready) => server.listen(0, '127.0.0.1', ready));
  origin = `http://127.0.0.1:${server.address().port}`;
  await new Promise((done, reject) => {
    const build = spawn('flutter', [
      'build', 'web', '--wasm', '--no-pub', '--no-web-resources-cdn',
      '--target=integration_test/support/session_account_browser_app.dart', `--output=${webDir}`,
      `--dart-define=SERVER_NAME=${origin}`, `--dart-define=WS_SERVER_NAME=${origin}`,
    ], { cwd: resolve('../../packages/client'), stdio: 'inherit' });
    build.on('error', reject);
    build.on('exit', (code) => code === 0 ? done() : reject(new Error(`Flutter build exited ${code}`)));
  });
  browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
}, { timeout: 300000 });

after(async () => {
  await browser?.close();
  for (const { socket } of connections) socket.terminate();
  sockets?.close();
  if (server) await new Promise((done) => server.close(done));
});

for (const [locale, notice] of [
  ['ru', 'Аккаунт изменён в другой вкладке. Перезагружаем…'],
  ['en', 'Your account changed in another tab. Reloading…'],
]) {
  for (const trigger of ['http', 'socket']) {
    test(`${trigger}: cookie account swap rejects B, shows ${locale} notice at 375x667, and reloads once`, { timeout: 45000 }, async () => {
      documents = 0;
      requests = [];
      frames = [];
      connections = [];
      const context = await browser.newContext({ viewport: { width: 375, height: 667 } });
      try {
        // A second tab changes the server cookie; JS cannot read or write it.
        const otherTab = await context.newPage();
        await otherTab.goto(`${origin}/cookie`);
        const signIn = (account) => otherTab.evaluate(async (account) => {
          const response = await fetch(`/session/${account}`, { method: 'POST', credentials: 'include' });
          return response.ok;
        }, account);
        assert.equal(await signIn('account-a'), true);
        const [cookie] = (await context.cookies()).filter((c) => c.name === cookieName);
        assert.equal(cookie.httpOnly, true);
        assert.equal(await otherTab.evaluate(() => document.cookie.includes('__Host-tentura_session')), false);

        const page = await context.newPage();
        const errors = [];
        let navigations = 0;
        page.on('pageerror', (error) => errors.push(String(error)));
        page.on('request', (request) => {
          if (request.isNavigationRequest() && request.frame() === page.mainFrame()) navigations++;
        });
        await page.goto(`${origin}/app?locale=${locale}`);
        await waitForAccount(page, 'account-a');
        const firstTimeOrigin = await page.evaluate(() => performance.timeOrigin);
        assert.deepEqual(await page.evaluate(async () => JSON.parse(await window.sessionAccountRead())), { archivedCount: 1 });
        assert.equal(requests.filter((r) => r.path.endsWith('/graphql')).at(-1).headers.authorization, `Bearer ${tokenA}`);
        assert.ok(frames.some(({ frame }) => frame.token === tokenA), 'Real socket authenticated as A');
        assert.equal(documents, 1);
        assert.equal(navigations, 1);

        const swapIndex = requests.length;
        assert.equal(await signIn('account-b'), true);
        if (trigger === 'http') {
          assert.deepEqual(await page.evaluate(async () => JSON.parse(await window.sessionAccountRead())), { error: 'accountChanged' });
        } else {
          connections.at(-1).socket.close(4000, 'Force a real reconnect after cookie replacement');
        }

        // Observe the actual rendered Flutter semantics before navigation.
        await page.waitForFunction((notice) => [...document.querySelectorAll('flt-semantics')].some((element) => {
          if ((element.textContent || '').trim() !== notice && element.getAttribute('aria-label') !== notice) return false;
          const box = element.getBoundingClientRect();
          return box.width > 0 && box.height > 0 && box.left >= 0 && box.top >= 0 &&
            box.right <= innerWidth && box.bottom <= innerHeight && getComputedStyle(element).visibility !== 'hidden';
        }), notice, { timeout: 10000 });
        assert.equal(documents, 1, 'Localized notice must be visible before unloading A');

        await waitForAccount(page, 'account-b');
        assert.equal(await page.evaluate(() => location.pathname), '/');
        assert.ok(await page.evaluate(() => performance.timeOrigin) > firstTimeOrigin, 'A new document, not an app remount');
        // Allow a second scheduled reload to expose itself after B bootstraps.
        await page.waitForTimeout(1500);
        assert.equal(documents, 2, 'Exactly one controlled reload');
        assert.equal(navigations, 2);
        assert.equal(await page.evaluate(() => sessionStorage.getItem('sessionAccount.noticeCount')), '1');
        assert.equal(await page.evaluate(() => sessionStorage.getItem('sessionAccount.notice')), 'accountChanged');
        assert.equal(await page.evaluate(() => sessionStorage.getItem('sessionAccount.flutterError')), null);
        assert.deepEqual(errors, []);
        assert.equal((await context.cookies()).find((c) => c.name === cookieName).value, 'account-b', 'Keep the valid replacement session');

        const whileBoundToA = requests.slice(swapIndex).filter((r) => r.document === 1);
        assert.ok(whileBoundToA.some((r) => r.path === '/api/v2/session/access-token' && r.subject === 'account-b'), 'Actually refreshed the replaced cookie');
        assert.equal(whileBoundToA.some((r) => JSON.stringify(r).includes(tokenB)), false, 'B bearer never leaves the A document via HTTP');
        assert.equal(frames.some(({ document, frame }) => document === 1 && JSON.stringify(frame).includes(tokenB)), false, 'B bearer never leaves the A document via WebSocket');
        if (trigger === 'http') assert.equal(whileBoundToA.some((r) => r.path.endsWith('/graphql')), false, 'Abort GraphQL before sending B bearer');
        if (trigger === 'socket') assert.ok(connections.filter((c) => c.document === 1).length >= 2, 'Exercise browser WebSocket reconnect authentication');
      } finally {
        await context.close();
      }
    });
  }
}

async function waitForAccount(page, account) {
  await page.waitForFunction((account) => {
    if (typeof window.sessionAccountState !== 'function') return false;
    const state = JSON.parse(window.sessionAccountState());
    return state.account === account && state.boundAccount === account && state.phase === 'authenticated';
  }, account, { timeout: 30000 });
}
