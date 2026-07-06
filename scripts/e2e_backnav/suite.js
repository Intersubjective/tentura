// Back-navigation regression suite for the adaptive-router refactor (Phase 2).
//
// Run via Playwright MCP `browser_run_code_unsafe` with `filename:` pointing
// here. Requires: local stack up (Caddy :9443, server :2080, hasura :8080),
// a signed-in QA session cookie in the browser profile (author QA user), and
// the QA fixture beacon B2332d32c0366 with an admitted helper U67b543012fca.
//
// Expectations marked STEP1+ flip when detail routes move inside the shell;
// edit the EXPECT block, not the scenarios.
async (page) => {
  const BASE = 'https://dev.lvh.me:9443';
  const BEACON = 'B2332d32c0366';
  const HELPER = 'U67b543012fca';
  const ME = 'Ua6432bd9e599';

  const EXPECT = {
    railOnBeaconDetail: true, // STEP1+: beacon view lives in a tab branch
    railOnGraphDetail: false, // STEP2 cohort 2 flips this
    bottomBarOnDetailCompact: false, // frozen: compact hides bottom bar on details
  };

  // STEP1+: beacon view is a branch child; cold-start legacy links land in
  // the default MyWork branch, warm pushes in the active tab's branch.
  const BEACON_VIEW_RE = new RegExp(`^#/home/[a-z]+/beacon/view/${BEACON}`);

  const results = [];
  const hash = () => page.evaluate(() => location.hash);
  const settle = (ms) => page.waitForTimeout(ms);

  async function enableSemantics() {
    const ph = page.locator('flt-semantics-placeholder');
    if ((await ph.count()) > 0) {
      try { await ph.first().click({ force: true, timeout: 3000 }); } catch (e) {}
    }
    await settle(1500);
  }

  // Full app load on a hash route + semantics. Used at scenario starts.
  async function boot(route, viewport) {
    await page.setViewportSize(viewport);
    // Same-origin hash-only navigation would NOT reload the app (warm
    // handoff); bounce through about:blank so every boot is a cold start.
    await page.goto('about:blank');
    await page.goto(`${BASE}/${route}`, { waitUntil: 'load' });
    await page.waitForTimeout(9000);
    await enableSemantics();
  }

  // In-app hash navigation (adds a history entry like a link click would).
  async function gotoHash(route) {
    await page.evaluate((r) => { location.hash = r; }, route);
    await settle(2500);
  }

  // Nav chrome present? The rail exposes "My people Tab 3 of 4" as accessible
  // text (no aria-label); the compact bar uses a plain "My people" aria-label.
  const railVisible = async () => {
    if ((await page.getByRole('button', { name: /My people.*Tab 3 of 4/s }).count()) > 0) {
      return true;
    }
    return page.evaluate(() =>
      [...document.querySelectorAll('[aria-label]')].some(
        (e) => (e.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim() === 'My people',
      )
    );
  };

  const desktop = { width: 1280, height: 800 };
  const compact = { width: 390, height: 844 };

  async function scenario(name, fn) {
    try {
      const detail = await fn();
      results.push({ name, pass: true, detail: detail ?? '' });
    } catch (e) {
      results.push({ name, pass: false, detail: String(e.message || e).slice(0, 300) });
    }
  }

  function expectEq(actual, expected, label) {
    if (actual !== expected) {
      throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }
  }
  function expectMatch(actual, re, label) {
    if (!re.test(actual)) {
      throw new Error(`${label}: ${JSON.stringify(actual)} !~ ${re}`);
    }
  }
  // Poll until an async predicate holds — semantics/URL updates lag behind
  // navigation on Flutter web, so single-shot asserts flake.
  async function until(fn, label, timeout = 8000) {
    const t0 = Date.now();
    let last;
    while (Date.now() - t0 < timeout) {
      last = await fn();
      if (last === true) return;
      await settle(300);
    }
    throw new Error(`${label}: not met within ${timeout}ms (last=${JSON.stringify(last)})`);
  }

  // ---- Desktop (>=600: rail chrome) -------------------------------------

  await scenario('D1 work tab -> beacon card -> browser back', async () => {
    await boot('#/home/work', desktop);
    await page.getByRole('button', { name: /Open Request QA publish 526219/ }).first().click();
    await settle(3000);
    expectMatch(await hash(), BEACON_VIEW_RE, 'after card click');
    expectEq(await railVisible(), EXPECT.railOnBeaconDetail, 'rail on beacon view');
    await page.goBack();
    await until(async () => (await hash()) === '#/home/work', 'after browser back');
    await until(railVisible, 'rail on home');
  });

  await scenario('D2 graph -> profile -> graph -> back x3', async () => {
    await boot('#/home/profile', desktop);
    await page.getByRole('button', { name: 'Show Connections' }).first().click();
    await settle(3500);
    expectMatch(await hash(), new RegExp(`^#/graph/${ME}`), 'graph 1');
    expectEq(await railVisible(), EXPECT.railOnGraphDetail, 'rail on graph');
    await gotoHash(`#/profile/view/${HELPER}`);
    expectMatch(await hash(), new RegExp(`^#/profile/view/${HELPER}`), 'profile view');
    await page.getByRole('button', { name: 'Show Connections' }).first().click();
    await settle(3500);
    expectMatch(await hash(), new RegExp(`^#/graph/${HELPER}`), 'graph 2');
    await page.goBack();
    await settle(2000);
    expectMatch(await hash(), new RegExp(`^#/profile/view/${HELPER}`), 'back to profile');
    await page.goBack();
    await settle(2000);
    expectMatch(await hash(), new RegExp(`^#/graph/${ME}`), 'back to graph 1');
    await page.goBack();
    await settle(2000);
    expectEq(await hash(), '#/home/profile', 'back to profile tab');
  });

  await scenario('D3 legacy /beacon/room/:id redirect (desktop: split pane)', async () => {
    await boot(`#/beacon/room/${BEACON}`, desktop);
    const h = await hash();
    expectMatch(h, BEACON_VIEW_RE, 'redirected to view');
    // Desktop >=840 strips tab=room and derives the Phase 1 split instead;
    // the room pane must be live (composer Attach affordance present).
    const attach = (await page.getByRole('button', { name: 'Attach' }).count()) > 0;
    if (!attach) throw new Error('room pane not visible after legacy room link');
  });

  await scenario('C0 compact legacy /beacon/room/:id keeps tab=room', async () => {
    await boot(`#/beacon/room/${BEACON}`, compact);
    const h = await hash();
    expectMatch(h, BEACON_VIEW_RE, 'redirected to view');
    expectMatch(h, /tab=room/, 'room tab preserved on compact');
    const attach = (await page.getByRole('button', { name: 'Attach' }).count()) > 0;
    if (!attach) throw new Error('room surface not visible on compact legacy room link');
  });

  await scenario('D4 legacy /beacon/:id redirect', async () => {
    await boot(`#/beacon/${BEACON}`, desktop);
    expectMatch(await hash(), BEACON_VIEW_RE, 'redirected to view');
  });

  await scenario('D5 refresh mid-stack: leading back falls back home', async () => {
    await boot(`#/beacon/view/${BEACON}?entry=my_work`, desktop);
    expectMatch(await hash(), BEACON_VIEW_RE, 'deep load');
    // Retry the leading Back once: the first semantics click after a cold
    // load occasionally lands before hit-testing is live.
    await page.getByRole('button', { name: 'Back' }).first().click();
    try {
      await until(async () => /^#\/home\//.test(await hash()), 'fallback to home', 5000);
    } catch (_) {
      await page.getByRole('button', { name: 'Back' }).first().click();
      await until(async () => /^#\/home\//.test(await hash()), 'fallback to home (retry)');
    }
  });

  await scenario('D6 notification-style /shared/view?dest=room link', async () => {
    await boot(`#/shared/view?id=${BEACON}&dest=room`, desktop);
    const h = await hash();
    expectMatch(h, new RegExp(`beacon/view/${BEACON}|beacon/room/${BEACON}`), 'lands on beacon');
  });

  await scenario('D7 tab switch keeps home URL mapping', async () => {
    await boot('#/home/work', desktop);
    await page.getByRole('button', { name: /Inbox.*Tab 2 of 4/ }).first().click();
    await settle(2000);
    expectEq(await hash(), '#/home/inbox', 'inbox tab URL');
    await page.getByRole('button', { name: /My people.*Tab 3 of 4/ }).first().click();
    await settle(2000);
    expectEq(await hash(), '#/home/network', 'network tab URL');
    await page.getByRole('button', { name: /My Work.*Tab 1 of 4/ }).first().click();
    await settle(2000);
    expectEq(await hash(), '#/home/work', 'work tab URL');
  });

  // ---- Compact (<600: bottom bar chrome) ---------------------------------

  await scenario('C1 compact: work -> beacon -> back, bottom bar rule', async () => {
    await boot('#/home/work', compact);
    await until(railVisible, 'bottom bar on home');
    await page.getByRole('button', { name: /Open Request QA publish 526219/ }).first().click();
    await until(async () => BEACON_VIEW_RE.test(await hash()), 'beacon view');
    await settle(1500);
    expectEq(await railVisible(), EXPECT.bottomBarOnDetailCompact, 'bottom bar on detail');
    await page.goBack();
    await until(async () => (await hash()) === '#/home/work', 'back to work');
  });

  await scenario('C2 compact: beacon -> Chat -> back -> back', async () => {
    await boot(`#/beacon/view/${BEACON}?entry=my_work`, compact);
    await page.getByRole('button', { name: 'Chat' }).first().click();
    await settle(2500);
    expectMatch(await hash(), /tab=room/, 'room open');
    await page.goBack();
    await settle(2000);
    const h = await hash();
    expectMatch(h, BEACON_VIEW_RE, 'room closed, view stays');
    if (/tab=room/.test(h)) throw new Error('room still in URL after back');
  });

  await scenario('C3 compact: full chain work -> beacon -> room -> back x3', async () => {
    await boot('#/home/work', compact);
    await page.getByRole('button', { name: /Open Request QA publish 526219/ }).first().click();
    await settle(3000);
    await page.getByRole('button', { name: 'Chat' }).first().click();
    await settle(2500);
    expectMatch(await hash(), /tab=room/, 'room open');
    await page.goBack();
    await settle(2000);
    expectMatch(await hash(), BEACON_VIEW_RE, 'back 1: view');
    await page.goBack();
    await settle(2000);
    expectEq(await hash(), '#/home/work', 'back 2: home');
  });

  // ---- Resize across the 600 boundary ------------------------------------

  await scenario('R1 resize 1280<->390 with beacon view open', async () => {
    await boot(`#/beacon/view/${BEACON}?entry=my_work`, desktop);
    await page.setViewportSize(compact);
    await settle(2500);
    expectMatch(await hash(), BEACON_VIEW_RE, 'hash stable after shrink');
    const chatVisible = (await page.getByRole('button', { name: 'Chat' }).count()) > 0;
    if (!chatVisible) throw new Error('compact beacon view missing Chat toggle after resize');
    await page.setViewportSize(desktop);
    await settle(2500);
    expectMatch(await hash(), BEACON_VIEW_RE, 'hash stable after grow');
    const errText = await page.evaluate(() => document.body.innerText.match(/RenderFlex|exception|Error/i)?.[0] ?? '');
    if (errText) throw new Error(`error text visible after resize: ${errText}`);
  });

  const summary = `${results.filter(r => r.pass).length}/${results.length} passed`;
  return { summary, results };
}
