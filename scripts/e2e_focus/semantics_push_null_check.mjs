#!/usr/bin/env node
/**
 * Browser pin for #746 / #916: flushSemantics null check after push/back/push.
 *
 * Bug: flutter/flutter#195316. On web, with semantics on, pushing a route,
 * popping it with browser Back and pushing again with a pointer tap throws
 * `Null check operator used on a null value` in
 * _RenderObjectSemantics._buildSemantics <- PipelineOwner.flushSemantics.
 * Upstream fix: flutter/flutter#192724, carried as a patch in our builder
 * image (scripts/flutter_patches/README.md). Before it: 14/14 on dev 7.60.18.
 *
 * Each cycle (1280x800, signed in): load/reload #/home/work (My work), wait
 * for semantics, pointer-click «+» (semantics button "New request"), wait,
 * history.back(), wait, pointer-click «+» again, wait. Console lines matching a Flutter
 * exception (null check / Another exception / EXCEPTION CAUGHT) and any
 * pageerror count as a hit for that cycle.
 *
 * Env:
 *   E2E_BASE_URL       default https://dev.tentura.io
 *   E2E_EMAIL          QA email for POST /api/v2/auth/email/test-login
 *                      (dev/staging only), default tab-qa-01@test.tentura.local
 *   E2E_USER_DATA_DIR  use this persistent Chromium profile (already signed
 *                      in) instead of test-login. Pass a COPY.
 *   E2E_CYCLES         default 5
 *   E2E_HEADED=1       headed browser
 *   E2E_IGNORE_HTTPS_ERRORS=1  for the local Caddy CA (https://dev.lvh.me:9443)
 *
 * Exit code: 0 no hits, 1 any hit, 2 could not set up (sign-in / app not
 * booting / «+» not found).
 */

import { chromium } from 'playwright';

const BASE = (process.env.E2E_BASE_URL || 'https://dev.tentura.io').replace(/\/+$/, '');
const EMAIL = process.env.E2E_EMAIL || 'tab-qa-01@test.tentura.local';
const USER_DATA_DIR = process.env.E2E_USER_DATA_DIR || '';
const HEADED = process.env.E2E_HEADED === '1';
const IGNORE_HTTPS = process.env.E2E_IGNORE_HTTPS_ERRORS === '1';
const CYCLES = Math.max(1, Number(process.env.E2E_CYCLES || 5));
const VIEWPORT = { width: 1280, height: 800 }; // the phone layout does not reproduce
const ERROR_RE = /Null check operator|Another exception was thrown|EXCEPTION CAUGHT BY/;

class SetupError extends Error {}
const settle = (page, ms) => page.waitForTimeout(ms);

async function signIn(context) {
  const res = await context.request.post(`${BASE}/api/v2/auth/email/test-login`, { data: { email: EMAIL } });
  if (!res.ok()) throw new SetupError(`test-login for ${EMAIL} → HTTP ${res.status()} (is QA_SIMPLE_LOGIN_MODE on at ${BASE}?)`);
}

/** Reload until <flutter-view> appears (a reload occasionally stalls the boot), then wait for semantics. */
async function loadApp(page) {
  await page.goto(`${BASE}/#/home/work`, { waitUntil: 'load' });
  let booted = false;
  for (let attempt = 0; attempt < 3 && !booted; attempt++) {
    await page.reload({ waitUntil: 'load' });
    booted = await page.waitForSelector('flutter-view', { state: 'attached', timeout: 40000 }).then(() => true, () => false);
  }
  if (!booted) throw new SetupError('Flutter app did not boot (no <flutter-view> after 3 reloads)');
  for (let i = 0; i < 60; i++) {
    if ((await page.locator('flt-semantics').count()) > 20) break;
    const ph = page.locator('flt-semantics-placeholder');
    if ((await ph.count()) > 0) await ph.first().click({ force: true, timeout: 3000 }).catch(() => {});
    await settle(page, 500);
  }
  if ((await page.locator('flt-semantics').count()) <= 2) throw new SetupError('semantics tree did not appear');
  await settle(page, 3000);
}

/** Centre of the on-screen «+» semantics node, or null. */
function findPlus(page) {
  return page.evaluate(([W, H]) => {
    const el = [...document.querySelectorAll('flt-semantics[role="button"]')].find((e) => {
      const label = (e.getAttribute('aria-label') || e.textContent || '').replace(/\s+/g, ' ').trim();
      if (label !== 'New request') return false;
      const r = e.getBoundingClientRect();
      return r.width > 0 && r.y >= 0 && r.y + r.height / 2 < H && r.x + r.width / 2 < W;
    });
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, [VIEWPORT.width, VIEWPORT.height]);
}

async function clickPlus(page, which) {
  const p = await findPlus(page);
  if (!p) throw new SetupError(`«+» (button "New request") not found for ${which} (hash ${await page.evaluate(() => location.hash)})`);
  await page.mouse.click(p.x, p.y);
  await settle(page, 1500);
}

async function main() {
  let browser = null;
  let context;
  const ctxOpts = { ignoreHTTPSErrors: IGNORE_HTTPS, locale: 'en-US', viewport: VIEWPORT };
  if (USER_DATA_DIR) {
    context = await chromium.launchPersistentContext(USER_DATA_DIR, { headless: !HEADED, ...ctxOpts });
  } else {
    browser = await chromium.launch({ headless: !HEADED });
    context = await browser.newContext(ctxOpts);
    await signIn(context);
  }
  let hits = 0;
  try {
    const page = context.pages()[0] || (await context.newPage());
    let errors = [];
    page.on('console', (m) => { const t = m.text(); if (ERROR_RE.test(t)) errors.push(t.split('\n')[0].slice(0, 160)); });
    page.on('pageerror', (e) => errors.push(`pageerror: ${String(e).split('\n')[0].slice(0, 160)}`));
    console.log('#746 / #916 flushSemantics null check: push «+», Back, push «+» (flutter/flutter#195316)');
    console.log(`base ${BASE}, ${VIEWPORT.width}x${VIEWPORT.height}, ${CYCLES} cycles, session ${USER_DATA_DIR ? 'persistent profile' : 'QA test-login'}`);
    for (let c = 1; c <= CYCLES; c++) {
      await loadApp(page);
      if (!(await page.evaluate(() => location.hash)).startsWith('#/home/work')) {
        throw new SetupError(`app left #/home/work (hash ${await page.evaluate(() => location.hash)}); signed out?`);
      }
      errors = [];
      await clickPlus(page, 'push #1');
      await page.evaluate(() => history.back());
      await settle(page, 1500);
      await clickPlus(page, 'push #2');
      await settle(page, 1000);
      const hit = errors.length > 0;
      if (hit) hits++;
      const hash = await page.evaluate(() => location.hash);
      console.log(`cycle ${c}: ${hit ? `HIT (${errors.length} lines) ${[...new Set(errors)].slice(0, 2).join(' | ')}` : 'clean'}  [hash ${hash}]`);
    }
  } finally {
    await context.close();
    if (browser) await browser.close();
  }
  console.log(`null-check hits: ${hits} of ${CYCLES} cycles`);
  console.log(hits ? 'RESULT: FAIL (RED)' : 'RESULT: PASS (GREEN)');
  return hits ? 1 : 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error(`SETUP ERROR: ${e instanceof SetupError ? e.message : e?.stack || e}`);
    process.exit(2);
  },
);
