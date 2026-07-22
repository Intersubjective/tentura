#!/usr/bin/env node
/**
 * Playwright integration test: Slack-like @mention in room chat.
 *
 * Covers:
 *   1. QA bootstrap (author + 3 helpers with shared handle prefix) + GraphQL setup
 *   2. Author UI: `@prefix` → several suggestions; ArrowDown selects 2nd; Enter sends
 *   3. Author UI: click/tap 3rd suggestion → send
 *   4. Unique @handle send → Postgres mentions[] + outbox kind=roomMention
 *
 * Prerequisites (local stack):
 *   - docker compose up (postgres, hasura, …)
 *   - ./scripts/run-server-local.sh          (:2080)
 *   - ./scripts/run-flutter-web-local.sh     (:8888)
 *   - caddy run --config Caddyfile.local     (:9443)
 *   - .env: QA_AUTH_ENABLED=true, QA_AUTH_TOKEN, QA_SIMPLE_LOGIN_MODE=true
 *
 * Run:
 *   cd scripts/e2e_mention && npm install && npm test
 */

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '../..');
const BASE = process.env.E2E_BASE_URL || 'https://dev.lvh.me:9443';
const API = process.env.E2E_API_URL || 'http://127.0.0.1:2080';
// Caddy uses an internal CA; Node fetch to BASE needs this for setup smoke.
process.env.NODE_TLS_REJECT_UNAUTHORIZED ??= '0';

function loadEnv() {
  const env = {};
  const raw = readFileSync(join(ROOT, '.env'), 'utf8');
  for (const line of raw.split('\n')) {
    if (!line || line.trim().startsWith('#')) continue;
    const i = line.indexOf('=');
    if (i < 0) continue;
    env[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return env;
}

const ENV = loadEnv();
const QA_TOKEN = process.env.QA_AUTH_TOKEN || ENV.QA_AUTH_TOKEN;
if (!QA_TOKEN) {
  console.error('QA_AUTH_TOKEN missing from env / .env');
  process.exit(1);
}

function sql(query) {
  const r = spawnSync(
    'docker',
    ['exec', '-i', 'postgres', 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-tAc', query],
    { encoding: 'utf8' },
  );
  if (r.status !== 0) {
    throw new Error(`psql failed: ${r.stderr || r.stdout}\nQ: ${query}`);
  }
  return (r.stdout || '').trim();
}

async function httpJson(url, { method = 'GET', headers = {}, body } = {}) {
  const res = await fetch(url, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`${method} ${url} → ${res.status}: ${text.slice(0, 400)}`);
  }
  return json;
}

async function gql(jwt, query, variables = {}) {
  const json = await httpJson(`${API}/api/v2/graphql`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
    body: { query, variables },
  });
  if (json.errors?.length) {
    throw new Error(`GraphQL errors: ${JSON.stringify(json.errors).slice(0, 600)}`);
  }
  return json.data;
}

async function testLoginJwt(email) {
  const jar = [];
  const loginRes = await fetch(`${API}/api/v2/auth/email/test-login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
    redirect: 'manual',
  });
  const setCookie = loginRes.headers.getSetCookie?.() || [];
  for (const c of setCookie) jar.push(c.split(';')[0]);
  const raw = loginRes.headers.get('set-cookie');
  if (!setCookie.length && raw) {
    for (const part of raw.split(/,(?=\s*__Host-|\s*[A-Za-z0-9_-]+=)/)) {
      jar.push(part.split(';')[0].trim());
    }
  }
  if (!jar.length) {
    const body = await loginRes.text();
    throw new Error(`test-login failed for ${email}: ${loginRes.status} ${body.slice(0, 300)}`);
  }
  // Endpoint is POST; body field is access_token (snake_case).
  const tokRes = await fetch(`${API}/api/v2/session/access-token`, {
    method: 'POST',
    headers: { Cookie: jar.join('; ') },
  });
  const tok = await tokRes.json();
  const jwt = tok.access_token || tok.accessToken;
  if (!jwt) {
    throw new Error(`no access_token for ${email}: ${JSON.stringify(tok)}`);
  }
  const session = jar
    .map((c) => c.split('='))
    .find(([n]) => n === '__Host-tentura_session');
  return {
    jwt,
    cookie: jar.join('; '),
    sessionValue: session ? session.slice(1).join('=') : null,
  };
}

async function installSessionCookie(context, sessionValue) {
  if (!sessionValue) throw new Error('missing session cookie value');
  await context.addCookies([
    {
      name: '__Host-tentura_session',
      value: sessionValue,
      url: `${BASE}/`,
      httpOnly: true,
      secure: true,
      sameSite: 'Lax',
    },
  ]);
}

function settle(page, ms) {
  return page.waitForTimeout(ms);
}

async function enableSemantics(page) {
  const ph = page.locator('flt-semantics-placeholder');
  if ((await ph.count()) > 0) {
    try {
      await ph.first().click({ force: true, timeout: 3000 });
    } catch {
      /* already enabled */
    }
  }
  await settle(page, 1200);
}

async function bootRoom(page, beaconId) {
  await page.goto('about:blank');
  await page.goto(`${BASE}/#/beacon/room/${beaconId}`, { waitUntil: 'load' });
  await settle(page, 10000);
  await enableSemantics(page);
  const attach = page.getByRole('button', { name: 'Attach' });
  const input = page.locator('[flt-semantics-identifier="room.message.input"]');
  const deadline = Date.now() + 35000;
  while (Date.now() < deadline) {
    if ((await attach.count()) > 0 || (await input.count()) > 0) return;
    const openChat = page.locator('[flt-semantics-identifier="beacon.room.open"]');
    if ((await openChat.count()) > 0) {
      await openChat.first().click({ force: true });
      await settle(page, 2500);
    }
    const chatTab = page.getByRole('button', { name: /^Chat$/i });
    if ((await chatTab.count()) > 0) {
      await chatTab.first().click({ force: true });
      await settle(page, 2000);
    }
    await settle(page, 500);
  }
  throw new Error('room composer (Attach) not visible');
}

async function focusComposer(page) {
  const byId = page.locator('[flt-semantics-identifier="room.message.input"]');
  if ((await byId.count()) > 0) {
    await byId.first().click({ force: true });
    await settle(page, 400);
    return;
  }
  const tf = page.getByRole('textbox');
  if ((await tf.count()) > 0) {
    await tf.last().click({ force: true });
    await settle(page, 400);
    return;
  }
  throw new Error('composer text field not found');
}

async function until(fn, label, timeout = 20000) {
  const t0 = Date.now();
  let last;
  while (Date.now() - t0 < timeout) {
    last = await fn();
    if (last) return last;
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`${label}: not met within ${timeout}ms (last=${JSON.stringify(last)})`);
}

async function bootstrapPair({ runId, authorEmail, helperEmail }) {
  return httpJson(`${API}/_qa/integration/bootstrap`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${QA_TOKEN}` },
    body: {
      runId,
      ...(authorEmail ? { authorEmail } : {}),
      ...(helperEmail ? { helperEmail } : {}),
    },
  });
}

async function admitHelper({ authorJwt, helperJwt, beaconId, helperUserId }) {
  await gql(
    authorJwt,
    `mutation($id: String!, $r: [String!]) {
      beaconForward(id: $id, recipientIds: $r, note: "please help")
    }`,
    { id: beaconId, r: [helperUserId] },
  );
  await gql(
    helperJwt,
    `mutation($id: String!) {
      beaconOfferHelp(id: $id, message: "I can help", helpTypes: ["software"])
    }`,
    { id: beaconId },
  );
  await gql(
    authorJwt,
    `mutation($b: String!, $u: String!) {
      BeaconRoomAdmit(beaconId: $b, participantUserId: $u)
    }`,
    { b: beaconId, u: helperUserId },
  );
  const access = sql(
    `SELECT room_access FROM public.beacon_participant
     WHERE beacon_id='${beaconId}' AND user_id='${helperUserId}'`,
  );
  if (access !== '3') {
    throw new Error(`helper ${helperUserId} not admitted (room_access=${access})`);
  }
}

async function clearComposer(page) {
  await focusComposer(page);
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await settle(page, 300);
}

async function sendComposer(page) {
  const send = page.locator('[flt-semantics-identifier="room.message.send"]');
  if ((await send.count()) > 0) {
    await send.first().click({ force: true });
  } else {
    await page.getByRole('button', { name: /send/i }).first().click({ force: true });
  }
  await settle(page, 2500);
}

function suggestionLocator(page, handle) {
  return page.locator(
    `[flt-semantics-identifier="room.mention.suggestion.${handle.toLowerCase()}"]`,
  );
}

async function waitForSuggestions(page, handles) {
  await until(async () => {
    for (const h of handles) {
      if ((await suggestionLocator(page, h).count()) === 0) return false;
    }
    return true;
  }, `suggestions for ${handles.join(',')}`, 15000);
}

async function suggestionOrder(page, handles) {
  // Document order of suggestion semantics nodes ≈ overlay list order.
  return page.evaluate((hs) => {
    const want = new Set(hs.map((h) => h.toLowerCase()));
    const ordered = [];
    for (const el of document.querySelectorAll('[flt-semantics-identifier]')) {
      const id = el.getAttribute('flt-semantics-identifier') || '';
      const m = /^room\.mention\.suggestion\.(.+)$/.exec(id);
      if (!m) continue;
      const h = m[1].toLowerCase();
      if (want.has(h) && !ordered.includes(h)) ordered.push(h);
    }
    return ordered;
  }, handles);
}

async function assertSelectedSuggestion(page, handle) {
  await until(async () => {
    return page.evaluate((h) => {
      const id = `room.mention.suggestion.${h.toLowerCase()}`;
      const nodes = [...document.querySelectorAll(`[flt-semantics-identifier="${id}"]`)];
      return nodes.some((n) => {
        const aria = (n.getAttribute('aria-selected') || '').toLowerCase();
        return aria === 'true' || n.getAttribute('aria-current') === 'true';
      });
    }, handle);
  }, `selected @${handle}`, 8000);
}

async function main() {
  const runId = `mention-${Date.now().toString(36)}`.slice(0, 64);
  const pfx = `sel${runId.replace(/[^a-z0-9]/g, '').slice(-6)}`;
  // Three handles sharing prefix `pfx` so typing `@pfx` yields multiple hints.
  const handles = [`${pfx}aa`, `${pfx}bb`, `${pfx}cc`];
  const markerKb = `MENTION_KB_${runId}`;
  const markerClick = `MENTION_CLICK_${runId}`;
  const markerUnique = `MENTION_E2E_${runId}`;
  console.log(`[e2e_mention] runId=${runId} prefix=@${pfx} handles=${handles.join(',')}`);

  const health = await fetch(`${API}/health`).then((r) => r.text());
  if (!health.includes('fine')) throw new Error(`API unhealthy: ${health}`);

  // 1) Bootstrap author + 3 helpers (shared author email on extras)
  const boot = await bootstrapPair({ runId });
  const { authorEmail, authorUserId } = boot;
  const helpers = [
    {
      email: boot.helperEmail,
      userId: boot.helperUserId,
      handle: handles[0],
    },
  ];
  for (let i = 1; i < handles.length; i++) {
    const extra = await bootstrapPair({
      runId: `${runId}-h${i}`.slice(0, 64),
      authorEmail,
      helperEmail: `it-helper-${runId}-h${i}@test.tentura.local`,
    });
    helpers.push({
      email: extra.helperEmail,
      userId: extra.helperUserId,
      handle: handles[i],
    });
  }
  console.log(
    `[e2e_mention] author=${authorUserId} helpers=${helpers.map((h) => h.userId).join(',')}`,
  );

  const authorAuth = await testLoginJwt(authorEmail);
  const helperAuths = [];
  for (const h of helpers) {
    const auth = await testLoginJwt(h.email);
    helperAuths.push(auth);
    await gql(
      auth.jwt,
      `mutation($h: String!) { userUpdate(handle: $h) { id handle } }`,
      { h: h.handle },
    );
  }

  // 2) Author creates request; admit all three helpers
  const created = await gql(
    authorAuth.jwt,
    `mutation($t: String!) {
      beaconCreate(title: $t, description: "mention e2e", draft: false) { id }
    }`,
    { t: `Mention E2E ${runId}` },
  );
  const beaconId = created.beaconCreate.id;
  console.log(`[e2e_mention] beacon=${beaconId}`);

  for (let i = 0; i < helpers.length; i++) {
    await admitHelper({
      authorJwt: authorAuth.jwt,
      helperJwt: helperAuths[i].jwt,
      beaconId,
      helperUserId: helpers[i].userId,
    });
  }

  const byHandle = Object.fromEntries(helpers.map((h) => [h.handle, h]));

  // 3) Playwright UI
  const browser = await chromium.launch({
    headless: process.env.E2E_HEADED !== '1',
  });
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: 1280, height: 800 },
    serviceWorkers: 'block',
  });
  // Prevent the app-cache SW from registering mid-test (cache-first, fixed
  // CACHE_VERSION — otherwise we silently run a stale/broken bundle).
  await context.addInitScript(() => {
    const noop = async () => ({
      unregister: async () => true,
      update: async () => undefined,
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        register: noop,
        getRegistration: async () => undefined,
        getRegistrations: async () => [],
        ready: Promise.resolve({ unregister: async () => true }),
        addEventListener() {},
        removeEventListener() {},
      },
    });
  });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);

  const results = [];
  async function scenario(name, fn) {
    try {
      const detail = await fn();
      results.push({ name, pass: true, detail: detail ?? '' });
      console.log(`  ✓ ${name}${detail ? ` — ${detail}` : ''}`);
    } catch (e) {
      results.push({ name, pass: false, detail: String(e.message || e).slice(0, 500) });
      console.error(`  ✗ ${name} — ${e.message || e}`);
      try {
        await page.screenshot({
          path: join(__dirname, `fail-${name.replace(/\W+/g, '_')}.png`),
          fullPage: true,
        });
      } catch {
        /* ignore */
      }
    }
  }

  await installSessionCookie(context, authorAuth.sessionValue);
  // Visit with cookie first so root-split serves the Flutter app (not landing).
  await page.goto(`${BASE}/`, { waitUntil: 'load' });
  await page.evaluate(async () => {
    try {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map((r) => r.unregister()));
    } catch {
      /* blocked */
    }
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch {
      /* ignore */
    }
  });
  await page.goto('about:blank');
  await page.goto(`${BASE}/#/home/work`, { waitUntil: 'load' });
  await settle(page, 10000);
  await enableSemantics(page);

  let roomReady = false;
  await scenario('UI open room composer', async () => {
    await bootRoom(page, beaconId);
    await focusComposer(page);
    roomReady = true;
    return 'composer focused';
  });

  async function requireRoom() {
    if (!roomReady) throw new Error('skipped: room composer not ready');
  }

  await scenario('UI shared-prefix shows several suggestions', async () => {
    await requireRoom();
    await clearComposer(page);
    await page.keyboard.type(`@${pfx}`, { delay: 60 });
    await settle(page, 1200);
    await waitForSuggestions(page, handles);
    const order = await suggestionOrder(page, handles);
    if (order.length !== handles.length) {
      throw new Error(`expected ${handles.length} suggestions, got ${JSON.stringify(order)}`);
    }
    // First row is selected by default.
    await assertSelectedSuggestion(page, order[0]);
    return `order=${order.join(',')}`;
  });

  await scenario('UI ArrowDown selects second alternative then Enter', async () => {
    await requireRoom();
    // Overlay should still be open from previous scenario; re-open if needed.
    if ((await suggestionLocator(page, handles[0]).count()) === 0) {
      await clearComposer(page);
      await page.keyboard.type(`@${pfx}`, { delay: 60 });
      await settle(page, 1200);
      await waitForSuggestions(page, handles);
    }
    const order = await suggestionOrder(page, handles);
    const target = order[1];
    if (!target) throw new Error(`need ≥2 suggestions, order=${JSON.stringify(order)}`);

    await focusComposer(page);
    await page.keyboard.press('ArrowDown');
    await settle(page, 400);
    await assertSelectedSuggestion(page, target);

    await page.keyboard.press('Enter');
    await settle(page, 600);
    await page.keyboard.type(` kb ${markerKb}`, { delay: 40 });
    await sendComposer(page);

    const row = await until(() => {
      const out = sql(
        `SELECT id || '|' || coalesce(array_to_string(mentions, ','), '') || '|' || body
         FROM public.beacon_room_message
         WHERE beacon_id='${beaconId}' AND body LIKE '%${markerKb}%'
         ORDER BY created_at DESC LIMIT 1`,
      );
      return out || null;
    }, 'kb message', 20000);
    const [, mentions, body] = row.split('|');
    const expectedUser = byHandle[target]?.userId;
    if (!body.toLowerCase().includes(`@${target}`)) {
      throw new Error(`body missing @${target}: ${body}`);
    }
    if (!mentions.split(',').includes(expectedUser)) {
      throw new Error(`mentions want ${expectedUser}, got ${mentions}`);
    }
    return `selected=${target}`;
  });

  await scenario('UI click/tap selects third alternative', async () => {
    await requireRoom();
    await clearComposer(page);
    await page.keyboard.type(`@${pfx}`, { delay: 60 });
    await settle(page, 1200);
    await waitForSuggestions(page, handles);
    const order = await suggestionOrder(page, handles);
    const target = order[2];
    if (!target) throw new Error(`need ≥3 suggestions, order=${JSON.stringify(order)}`);
    const targetIndex = 2;

    // Prefer accessible name click; fall back to pointer hit on row geometry.
    const byRole = page.getByRole('button', { name: new RegExp(`^@${target}$`, 'i') });
    if ((await byRole.count()) > 0) {
      await byRole.first().hover({ force: true });
      await settle(page, 200);
      await assertSelectedSuggestion(page, target);
      await byRole.first().click({ force: true });
    } else {
      const firstBox = await suggestionLocator(page, order[0]).first().boundingBox();
      let targetBox = await suggestionLocator(page, target).first().boundingBox();
      if (!targetBox || targetBox.height < 8) {
        if (!firstBox) throw new Error('no bounding box for first suggestion');
        const rowH = firstBox.height >= 8 ? firstBox.height : 56;
        targetBox = {
          x: firstBox.x,
          y: firstBox.y + rowH * targetIndex,
          width: Math.max(firstBox.width, 120),
          height: rowH,
        };
      }
      await page.mouse.move(
        targetBox.x + targetBox.width / 2,
        targetBox.y + targetBox.height / 2,
      );
      await settle(page, 250);
      await assertSelectedSuggestion(page, target);
      await page.mouse.click(
        targetBox.x + targetBox.width / 2,
        targetBox.y + targetBox.height / 2,
      );
    }
    await settle(page, 800);
    await until(
      async () => (await suggestionLocator(page, target).count()) === 0,
      'overlay dismissed after click',
      8000,
    );
    // Re-focus and type slowly — CanvasKit often drops keys right after overlay click.
    await focusComposer(page);
    await page.keyboard.press('End');
    await page.keyboard.type(` click ${markerClick}`, { delay: 70 });
    await settle(page, 800);
    await sendComposer(page);

    const db = await until(() => {
      const out = sql(
        `SELECT id || '|' || coalesce(array_to_string(mentions, ','), '') || '|' || body
         FROM public.beacon_room_message
         WHERE beacon_id='${beaconId}' AND body LIKE '%${markerClick}%'
         ORDER BY created_at DESC LIMIT 1`,
      );
      return out || null;
    }, 'click message', 20000);
    const [, mentions, body] = db.split('|');
    const expectedUser = byHandle[target]?.userId;
    if (!body.toLowerCase().includes(`@${target}`)) {
      throw new Error(`body missing @${target}: ${body}`);
    }
    if (!mentions.split(',').includes(expectedUser)) {
      throw new Error(`mentions want ${expectedUser}, got ${mentions}`);
    }
    return `clicked=${target}`;
  });

  await scenario('UI unique @handle + send (outbox path)', async () => {
    await requireRoom();
    const handle = handles[0];
    await clearComposer(page);
    await page.keyboard.type(`@${handle}`, { delay: 60 });
    await settle(page, 1200);
    await waitForSuggestions(page, [handle]);
    await page.keyboard.press('Enter');
    await settle(page, 600);
    await page.keyboard.type(` please see ${markerUnique}`, { delay: 40 });
    await sendComposer(page);
    return `sent @${handle}`;
  });

  await scenario('DB message stores mentions[]', async () => {
    const helperUserId = helpers[0].userId;
    const row = await until(() => {
      const out = sql(
        `SELECT id || '|' || coalesce(array_to_string(mentions, ','), '') || '|' || body
         FROM public.beacon_room_message
         WHERE beacon_id='${beaconId}' AND body LIKE '%${markerUnique}%'
         ORDER BY created_at DESC LIMIT 1`,
      );
      return out || null;
    }, 'message with marker', 20000);
    const [, mentions, body] = row.split('|');
    if (!mentions.split(',').includes(helperUserId)) {
      throw new Error(`mentions missing helper: ${mentions} body=${body}`);
    }
    return row.slice(0, 120);
  });

  await scenario('DB outbox roomMention for helper', async () => {
    const helperUserId = helpers[0].userId;
    const row = await until(() => {
      const out = sql(
        `SELECT id || '|' || kind || '|' || category || '|' || coalesce(source_event_key,'')
         FROM public.notification_outbox
         WHERE account_id='${helperUserId}'
           AND kind='roomMention'
           AND created_at > now() - interval '15 minutes'
         ORDER BY created_at DESC LIMIT 1`,
      );
      return out || null;
    }, 'outbox roomMention', 20000);
    if (!row.includes('|coordination|')) {
      throw new Error(`expected category=coordination: ${row}`);
    }
    return row.slice(0, 160);
  });

  await scenario('DB ambient roomActivity not for mentionee on same message', async () => {
    const helperUserId = helpers[0].userId;
    const ambient = sql(
      `SELECT count(*) FROM public.notification_outbox
       WHERE account_id='${helperUserId}'
         AND kind='roomActivityLowPriority'
         AND created_at > now() - interval '15 minutes'
         AND source_event_key LIKE 'room_message:%'`,
    );
    return `ambient_room_message_rows=${ambient}`;
  });

  await browser.close();

  const failed = results.filter((r) => !r.pass);
  console.log('\n[e2e_mention] summary');
  for (const r of results) {
    console.log(`  ${r.pass ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? ` — ${r.detail}` : ''}`);
  }
  if (failed.length) {
    console.error(`\n${failed.length} failed`);
    process.exit(1);
  }
  console.log(`\nAll ${results.length} scenarios passed.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
