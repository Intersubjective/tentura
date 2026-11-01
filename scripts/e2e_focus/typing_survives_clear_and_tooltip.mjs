// Real Chrome keyboard events against the real, semantics-on application.
// Adapted from jules-ctl/artifacts/603/trace603.js. No DOM fill(), synthetic
// blur, focus repair, mocked transport, or WidgetTester input is used here.
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.BASE || 'https://dev.lvh.me:9443';
let route = process.env.ROUTE || '/#/rating';
const fieldLabel = process.env.FIELD_LABEL || 'Search people';
const clearLabel = process.env.CLEAR_LABEL || 'Close';
const hoverLabel = process.env.HOVER_LABEL || clearLabel;
const mode = process.argv[2] || 'close';
const cycles = Number(process.argv[3] || 10);
assert.ok(['close', 'hover', 'backspace'].includes(mode), 'mode: close | hover | backspace');
assert.ok(Number.isInteger(cycles) && cycles >= 10, 'Use at least ten cycles');
const reset = (process.env.RESET_XY || '640,600').split(',').map(Number);
assert.ok(reset.length === 2 && reset.every(Number.isFinite), 'RESET_XY must be x,y');

let browser;
let page;
let deleteRequest;
try {
  browser = await chromium.launch({
    channel: 'chrome', headless: process.env.HEADLESS !== '0', args: ['--no-sandbox'],
  });
  const context = await browser.newContext({
    ignoreHTTPSErrors: true, viewport: { width: 1280, height: 800 },
    // Always execute the build served by this run, never a cached old app.
    serviceWorkers: 'block',
    locale: 'en-US',
  });
  const login = await context.request.post(`${base}/api/v2/auth/email/test-login`, {
    data: { email: process.env.EMAIL || 'society-bravo3@test.tentura.local' },
  });
  assert.equal(login.ok(), true, `QA login prerequisite: HTTP ${login.status()}`);
  if (route.includes('{requestId}')) {
    const tokenResponse = await context.request.post(`${base}/api/v2/session/access-token`);
    assert.equal(tokenResponse.ok(), true, 'Request fixture authentication');
    const { access_token: token } = await tokenResponse.json();
    assert.ok(token, 'Request fixture access token');
    const gql = async (query, variables) => {
      const response = await context.request.post(`${base}/api/v2/graphql`, {
        headers: { Authorization: `Bearer ${token}` }, data: { query, variables },
      });
      assert.equal(response.ok(), true, 'Request fixture HTTP response');
      const body = await response.json();
      assert.ok(!body.errors?.length, `Request fixture GraphQL: ${JSON.stringify(body.errors)}`);
      return body.data;
    };
    const created = await gql(
      'mutation { beaconCreate(title: "Typing across tooltip transitions", description: "Browser focus regression fixture", draft: false, isDiscoverable: false) { id } }',
    );
    const id = created.beaconCreate.id;
    assert.ok(id, 'Real Request fixture created through the public API');
    deleteRequest = () => gql('mutation($id: String!) { beaconDeleteById(id: $id) }', { id });
    route = route.replaceAll('{requestId}', id);
  }
  page = await context.newPage();
  page.setDefaultTimeout(15000);
  let wasmLoaded = false;
  page.on('response', (response) => {
    if (new URL(response.url()).pathname.endsWith('/main.dart.wasm') && response.ok()) wasmLoaded = true;
  });
  await page.addInitScript(() => {
    window.focusTrace = [];
    for (const type of ['focusin', 'focusout', 'keydown', 'input']) {
      document.addEventListener(type, (event) => {
        window.focusTrace.push({
          type, key: event.key, tag: event.target.tagName,
          active: document.activeElement?.tagName,
        });
        if (window.focusTrace.length > 100) window.focusTrace.shift();
      }, true);
    }
  });
  await page.goto(`${base}${route}`);
  // The profile app enables semantics itself, exactly as the dev deployment
  // does. A missing semantics tree is a setup failure, not a red regression.
  await page.locator('flt-semantics').first().waitFor({ state: 'attached', timeout: 60000 });
  assert.equal(wasmLoaded, true, 'Prerequisite: serve a --profile --wasm build via run.sh');
  assert.equal(await page.evaluate(() => crossOriginIsolated), true, 'Deployment isolation headers required');

  // The empty-results panel can repeat the clear action below the field.
  // The field's own clear/tooltip action is the first one in reading order.
  const button = (label) => page.getByRole('button', { name: label, exact: true }).first();
  if (process.env.PRE_CLICK_LABEL) await button(process.env.PRE_CLICK_LABEL).click();
  // Flutter merges a field's hint and its explicit semantics label. Accept
  // repeated copies of the same name, while still identifying only this field.
  const escapedLabel = fieldLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const fieldName = new RegExp(`^${escapedLabel}(?:\\s+${escapedLabel})*$`);
  const textbox = () => page.getByRole('textbox', { name: fieldName });
  const fieldBox = async () => {
    const labeled = textbox();
    await labeled.waitFor({ state: 'visible' });
    const box = await labeled.boundingBox();
    assert.ok(box && box.width > 0 && box.height > 0, `Visible field: ${fieldLabel}`);
    return { x: Math.round(box.x + Math.min(40, box.width / 2)), y: Math.round(box.y + box.height / 2), centerX: Math.round(box.x + box.width / 2) };
  };
  // Scope by accessible name where possible; no first-input fallback that
  // could accidentally assert a hidden engine editing element's value.
  const value = () => textbox().inputValue();
  const expectValue = async (expected, message) => {
    for (let attempt = 0; attempt < 20; attempt++) {
      if (await value() === expected) break;
      await page.waitForTimeout(250);
    }
    assert.equal(await value(), expected, message);
  };
  const clickCenter = async (locator) => {
    const box = await locator.boundingBox();
    assert.ok(box && box.width > 0 && box.height > 0, 'Visible action prerequisite');
    // Integer coordinates reproduce Chrome's real click activation path.
    await page.mouse.click(Math.round(box.x + box.width / 2), Math.round(box.y + box.height / 2));
  };
  const waitForTooltip = (visible) => page.waitForFunction(({ label, visible }) => {
    // The button retains its own accessible name when the tooltip disappears.
    // Observe the separate tooltip text, never that permanent button label.
    const shown = [...document.querySelectorAll('flt-semantics')].some((element) => {
      if (element.closest('[role="button"]') || element.querySelector('[role="button"]')) return false;
      if ((element.textContent || '').trim() !== label && element.getAttribute('aria-label') !== label) return false;
      const bounds = element.getBoundingClientRect();
      return bounds.width > 0 && bounds.height > 0 && getComputedStyle(element).visibility !== 'hidden';
    });
    return shown === visible;
  }, { label: hoverLabel, visible }, { timeout: 5000 });
  const results = [];
  for (let cycle = 1; cycle <= cycles; cycle++) {
    await page.mouse.click(...reset);
    const box = await fieldBox();
    await page.mouse.click(box.x, box.y);
    await page.waitForTimeout(400);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(200);
    await page.keyboard.type('Bo', { delay: 80 });
    await expectValue('Bo', `Cycle ${cycle} prerequisite: typing reaches the field before the action`);
    await page.evaluate(() => { window.focusTrace = []; });

    const checkpoints = [];
    if (mode === 'hover') {
      await button(hoverLabel).hover();
      // Flutter's tooltip has a hover delay. Let both its semantics wrapper
      // insertion and the engine's deferred blur execute before typing.
      await page.waitForTimeout(1500);
      await waitForTooltip(true);
      await page.keyboard.type('Xx', { delay: 80 });
      await page.waitForTimeout(400);
      checkpoints.push({ action: 'typing while tooltip is visible', expected: 'BoXx', actual: await value() });
      await page.mouse.move(...reset, { steps: 8 });
      await page.waitForTimeout(1000);
      await waitForTooltip(false);
      await page.keyboard.type('Yy', { delay: 80 });
      await page.waitForTimeout(400);
      checkpoints.push({ action: 'typing after tooltip hides', expected: 'BoXxYy', actual: await value() });
    } else {
      if (mode === 'close') await clickCenter(button(clearLabel));
      else {
        await page.keyboard.press('Backspace');
        await page.keyboard.press('Backspace');
      }
      await expectValue('', `Cycle ${cycle}: clearing removes the visible query`);
      await page.waitForTimeout(700);
      await page.keyboard.type('Zz', { delay: 80 });
      await page.waitForTimeout(500);
      checkpoints.push({ action: 'typing immediately after clear', expected: 'Zz', actual: await value() });
      // A single ordinary click must also leave the field usable, even if
      // the first keys were lost. Never repair focus with a second click.
      // Click beyond the short query: Updates has a leading search icon, so
      // the initial 40px focus point would put the caret before its text.
      const nextBox = await fieldBox();
      await page.mouse.click(nextBox.centerX, nextBox.y);
      await page.waitForTimeout(600);
      await page.keyboard.type('Ca', { delay: 80 });
      await page.waitForTimeout(500);
      checkpoints.push({ action: 'typing after one field click', expected: 'ZzCa', actual: await value() });
    }
    const failed = checkpoints.some(({ actual, expected }) => actual !== expected);
    const result = { cycle, checkpoints, ...(failed ? { trace: await page.evaluate(() => window.focusTrace) } : {}) };
    results.push(result);
    console.log(JSON.stringify(result));
  }
  const failures = results.filter(({ checkpoints }) => checkpoints.some(({ actual, expected }) => actual !== expected));
  console.log(`${failures.length ? 'FAIL' : 'PASS'} ${route} ${mode}: ${failures.length}/${cycles} cycles lost typed keys`);
  // Exit 2 is exclusively a demonstrated lost-key regression; setup errors
  // (login, missing field/button/build) exit 1 and cannot count as evidence.
  process.exitCode = failures.length ? 2 : 0;
} catch (error) {
  console.error(error);
  if (page) console.error('Setup diagnostics:', await page.evaluate(() => ({
    route: location.hash,
    fields: [...document.querySelectorAll('input,textarea')].map((element) => element.outerHTML),
    semantics: [...document.querySelectorAll('flt-semantics')].map((element) => ({
      role: element.getAttribute('role'), label: element.getAttribute('aria-label'),
      text: element.textContent?.slice(0, 100),
    })).filter(({ label, text }) => label || text).slice(0, 40),
  })));
  process.exitCode = 1;
} finally {
  try {
    await deleteRequest?.();
  } catch (error) {
    console.error('Request fixture cleanup failed:', error);
    process.exitCode = 1;
  }
  await browser?.close();
}
