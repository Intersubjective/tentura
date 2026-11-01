#!/usr/bin/env node
/**
 * Browser pin for #927: keyboard focus after a cold deep link to the Graph.
 *
 * Bug: a cold load of `#/graph/<id>` (or a reload of it) builds Home under
 * the Graph in the same frame. On main, Home's tab shell is built offstage
 * and never laid out, so the first Tab / Shift+Tab sorts Home's focus nodes
 * and throws `RenderBox was not laid out`; focus stays on <flutter-view>.
 *
 * For each viewport (desktop rail, phone bottom bar) this script runs:
 *   1. cold load  <BASE>/#/graph/<id>, first key Tab
 *   2. reload,    first key Shift+Tab
 *   3. reload,    first key Tab
 * and after each key of  [first, Tab, Shift+Tab, Tab]  asserts that
 *   - document.activeElement is a <flt-semantics> node (Flutter web moves DOM
 *     focus onto the semantics node of the framework's primary focus), and
 *   - it is not inside Home's shell (Home's nav items are not in the
 *     semantics tree), and the URL is still #/graph/<id>;
 * and over the whole scenario that the console carries no
 * `RenderBox was not laid out`, no other Flutter exception and no pageerror.
 *
 * Env:
 *   E2E_BASE_URL       default https://dev.tentura.io
 *   E2E_USER_ID        user whose graph to open; default: the signed-in user
 *   E2E_EMAIL          QA email for POST /api/v2/auth/email/test-login
 *                      (dev/staging only), default tab-qa-01@test.tentura.local
 *   E2E_USER_DATA_DIR  use this persistent Chromium profile (already signed
 *                      in) instead of test-login. Pass a COPY: Chromium writes
 *                      into it.
 *   E2E_VIEWPORTS      comma list of WxH, default 1280x800,375x667
 *   E2E_HEADED=1       headed browser
 *   E2E_IGNORE_HTTPS_ERRORS=1  for the local Caddy CA (https://dev.lvh.me:9443)
 *   E2E_LOCAL_BUILD_DIR  serve this `flutter build web` output as BASE's app
 *                      shell (index.html, bootstrap, wasm, assets) while
 *                      /api/** and anything not in the dir go to BASE live:
 *                      a pre-deploy run of a local build against dev's backend
 *                      and session, same origin.
 *
 * Exit code: 0 pass, 1 fail (2 = could not set up: sign-in / app not booting).
 */

import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { chromium } from 'playwright';

const BASE = (process.env.E2E_BASE_URL || 'https://dev.tentura.io').replace(/\/+$/, '');
const EMAIL = process.env.E2E_EMAIL || 'tab-qa-01@test.tentura.local';
const USER_DATA_DIR = process.env.E2E_USER_DATA_DIR || '';
const HEADED = process.env.E2E_HEADED === '1';
const IGNORE_HTTPS = process.env.E2E_IGNORE_HTTPS_ERRORS === '1';
const LOCAL_BUILD_DIR = process.env.E2E_LOCAL_BUILD_DIR || '';
const VIEWPORTS = (process.env.E2E_VIEWPORTS || '1280x800,375x667')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)
  .map((s) => {
    const [width, height] = s.split('x').map(Number);
    return { width, height, name: `${width}x${height}` };
  });

// Home shell nav item (packages/client/lib/ui/test_ids.dart).
const HOME_SHELL_IDS = ['constellation.nav_item'];

// Console lines that are a Flutter framework error, not app noise.
const FLUTTER_ERROR_RE =
  /RenderBox was not laid out|EXCEPTION CAUGHT BY|Another exception was thrown|Bad state:|Null check operator used on a null value|Unexpected null value|Uncaught/;

const settle = (page, ms) => page.waitForTimeout(ms);

class SetupError extends Error {}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.frag': 'application/octet-stream', '.symbols': 'text/plain',
};

/** Serve a local web build as BASE's app shell; the API and the rest stay live. */
async function serveLocalBuild(context) {
  const root = normalize(LOCAL_BUILD_DIR);
  if (!existsSync(join(root, 'index.html'))) throw new SetupError(`no index.html in E2E_LOCAL_BUILD_DIR`);
  await context.route(`${BASE}/**`, async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith('/api/')) return route.continue();
    const rel = url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname.slice(1));
    const file = normalize(join(root, rel));
    if (!file.startsWith(root) || !existsSync(file) || !statSync(file).isFile()) return route.continue();
    return route.fulfill({
      status: 200,
      body: readFileSync(file),
      headers: { 'content-type': MIME[extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' },
    });
  });
}

async function signIn(context) {
  const res = await context.request.post(`${BASE}/api/v2/auth/email/test-login`, {
    data: { email: EMAIL },
  });
  if (!res.ok()) {
    throw new SetupError(`test-login for ${EMAIL} → HTTP ${res.status()} (is QA_SIMPLE_LOGIN_MODE on at ${BASE}?)`);
  }
}

/** The signed-in user's id, read from the access token's `sub` (never printed). */
async function signedInUserId(context) {
  const res = await context.request.post(`${BASE}/api/v2/session/access-token`);
  if (!res.ok()) throw new SetupError(`no session at ${BASE} (access-token → HTTP ${res.status()})`);
  const body = await res.json();
  const jwt = body.access_token || body.accessToken;
  if (!jwt) throw new SetupError('access-token answer carried no token');
  const sub = JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString()).sub;
  if (!sub) throw new SetupError('access token has no sub');
  return sub;
}

async function clearAppCache(page) {
  // The app-cache service worker is cache-first; drop it so the deployed
  // bundle is what runs (same as scripts/e2e_backnav).
  await page.goto(`${BASE}/`, { waitUntil: 'load' });
  await page.evaluate(async () => {
    const regs = (await navigator.serviceWorker?.getRegistrations?.()) || [];
    await Promise.all(regs.map((r) => r.unregister()));
    if (globalThis.caches) {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    }
  });
}

async function waitForApp(page) {
  try {
    await page.waitForSelector('flutter-view', { state: 'attached', timeout: 60000 });
  } catch {
    const tags = await page.evaluate(() => [...new Set([...document.querySelectorAll('body *')].map((e) => e.tagName.toLowerCase()))].slice(0, 15).join(','));
    throw new SetupError(`Flutter app did not boot (no <flutter-view> within 60 s; url ${page.url().replace(/#.*$/, '#…')}; body tags ${tags})`);
  }
  await settle(page, 6000); // first frames, graph fetch, route stack
  // Non-prod builds enable semantics themselves after layout settles; on a
  // build that does not, the placeholder click turns them on.
  for (let i = 0; i < 30; i++) {
    if ((await page.locator('flt-semantics').count()) > 2) break;
    const ph = page.locator('flt-semantics-placeholder');
    if ((await ph.count()) > 0) await ph.first().click({ force: true, timeout: 3000 }).catch(() => {});
    await settle(page, 500);
  }
  if ((await page.locator('flt-semantics').count()) <= 2) {
    throw new SetupError('semantics tree did not appear');
  }
  await settle(page, 1000);
}

function describeFocus(page, homeIds) {
  return page.evaluate((ids) => {
    const a = document.activeElement;
    if (!a) return { tag: null };
    const inHome = ids.some((id) => a.closest(`[flt-semantics-identifier="${id}"]`));
    const homeOnStage = ids.some((id) => document.querySelector(`[flt-semantics-identifier="${id}"]`));
    const label = (a.getAttribute('aria-label') || a.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40);
    return { tag: a.tagName.toLowerCase(), id: a.id || '', role: a.getAttribute('role') || '', label, inHome, homeOnStage, hash: location.hash };
  }, homeIds);
}

async function runScenario(page, { name, load, firstKey, graphHash }) {
  const errors = [];
  const onConsole = (m) => {
    const text = m.text();
    if (process.env.E2E_DEBUG === '1') console.log(`      [${m.type()}] ${text.split('\n')[0].slice(0, 160)}`);
    if ((m.type() === 'error' || m.type() === 'warning') && FLUTTER_ERROR_RE.test(text)) {
      errors.push(`console.${m.type()}: ${text.split('\n')[0].slice(0, 200)}`);
    }
  };
  const onPageError = (e) => errors.push(`pageerror: ${String(e).split('\n')[0].slice(0, 200)}`);
  page.on('console', onConsole);
  page.on('pageerror', onPageError);

  const lines = [];
  const failures = [];
  try {
    await load();
    await waitForApp(page);
    const start = await describeFocus(page, HOME_SHELL_IDS);
    if (!start.hash.startsWith(graphHash)) {
      throw new SetupError(`app did not stay on ${graphHash} (hash ${start.hash}); signed out or user unknown?`);
    }
    lines.push(`    before keys: <${start.tag}${start.id ? '#' + start.id : ''}>`);
    const keys = [firstKey, 'Tab', 'Shift+Tab', 'Tab'];
    for (let i = 0; i < keys.length; i++) {
      await page.keyboard.press(keys[i]);
      await settle(page, 700);
      const f = await describeFocus(page, HOME_SHELL_IDS);
      const problems = [];
      if (f.tag !== 'flt-semantics') problems.push(`focus on <${f.tag}>, not a semantics node`);
      if (f.inHome) problems.push("focus inside Home's shell");
      if (f.homeOnStage) problems.push("Home's shell is in the semantics tree");
      if (!f.hash.startsWith(graphHash)) problems.push(`left the Graph (hash ${f.hash})`);
      const where = f.tag === 'flt-semantics' ? `<flt-semantics ${f.role || '-'} "${f.label}">` : `<${f.tag}>`;
      lines.push(`    ${String(i + 1)}. ${keys[i].padEnd(9)} → ${where}${problems.length ? '  ✗ ' + problems.join('; ') : '  ✓'}`);
      for (const p of problems) failures.push(`key ${i + 1} (${keys[i]}): ${p}`);
    }
    await settle(page, 500);
  } finally {
    page.off('console', onConsole);
    page.off('pageerror', onPageError);
  }
  for (const e of [...new Set(errors)]) failures.push(e);
  if (errors.length) lines.push(`    errors: ${[...new Set(errors)].join(' | ')}`);
  return { name, ok: failures.length === 0, lines, failures };
}

async function main() {
  let browser = null;
  let context;
  const launchOpts = { headless: !HEADED };
  const ctxOpts = { ignoreHTTPSErrors: IGNORE_HTTPS, locale: 'en-US', viewport: VIEWPORTS[0] };
  if (USER_DATA_DIR) {
    context = await chromium.launchPersistentContext(USER_DATA_DIR, { ...launchOpts, ...ctxOpts });
  } else {
    browser = await chromium.launch(launchOpts);
    context = await browser.newContext(ctxOpts);
    await signIn(context);
  }
  if (LOCAL_BUILD_DIR) await serveLocalBuild(context);
  const results = [];
  try {
    const userId = process.env.E2E_USER_ID || (await signedInUserId(context));
    const graphHash = `#/graph/${userId}`;
    const url = `${BASE}/${graphHash}`;
    const page = context.pages()[0] || (await context.newPage());
    console.log(`#927 cold Graph deep link: focus traversal`);
    console.log(`base ${BASE}, route ${graphHash}, session ${USER_DATA_DIR ? 'persistent profile' : 'QA test-login'}`);
    // A fresh context has no service worker; a reused profile may hold one.
    if (USER_DATA_DIR) await clearAppCache(page);
    else await page.goto(`${BASE}/`, { waitUntil: 'load' });
    const build = await page.evaluate(() =>
      [...document.querySelectorAll('script[src],link[href]')]
        .map((e) => e.src || e.href)
        .map((u) => /app-assets\/([^/]+)\//.exec(u)?.[1])
        .find(Boolean) || 'unknown');
    console.log(`app build ${LOCAL_BUILD_DIR ? `local (E2E_LOCAL_BUILD_DIR), ${build}` : build}`);

    for (const vp of VIEWPORTS) {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      const scenarios = [
        {
          name: `${vp.name} cold load, first Tab`,
          firstKey: 'Tab',
          // about:blank bounce: a same-origin hash change would be a warm handoff
          load: async () => { await page.goto('about:blank'); await page.goto(url, { waitUntil: 'load' }); },
        },
        { name: `${vp.name} reload, first Shift+Tab`, firstKey: 'Shift+Tab', load: () => page.reload({ waitUntil: 'load' }) },
        { name: `${vp.name} reload, first Tab`, firstKey: 'Tab', load: () => page.reload({ waitUntil: 'load' }) },
      ];
      for (const s of scenarios) {
        const r = await runScenario(page, { ...s, graphHash });
        results.push(r);
        console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}`);
        for (const l of r.lines) console.log(l);
      }
    }
  } finally {
    await context.close();
    if (browser) await browser.close();
  }
  const failed = results.filter((r) => !r.ok);
  console.log('');
  console.log(`SUMMARY: ${results.length - failed.length}/${results.length} scenarios passed`);
  for (const r of failed) {
    console.log(`  FAIL ${r.name}`);
    for (const f of [...new Set(r.failures)]) console.log(`       - ${f}`);
  }
  console.log(failed.length ? 'RESULT: FAIL (RED)' : 'RESULT: PASS (GREEN)');
  return failed.length ? 1 : 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error(`SETUP ERROR: ${e instanceof SetupError ? e.message : e?.stack || e}`);
    process.exit(2);
  },
);
