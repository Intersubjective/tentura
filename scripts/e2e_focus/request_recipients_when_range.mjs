// Real browser input, ensureDraft, and Recipients on the deployed application.
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.E2E_BASE_URL || 'https://dev.tentura.io';
const browser = await chromium.launch({
  channel: 'chrome', headless: true, args: ['--no-sandbox'],
});
const context = await browser.newContext({
  viewport: { width: 375, height: 667 }, locale: 'en-US',
  timezoneId: 'Europe/Amsterdam', serviceWorkers: 'block',
});
const page = await context.newPage();
page.setDefaultTimeout(15000);
const ids = new Set();
const operations = [];
const pending = new Set();
page.on('response', (response) => {
  const request = response.request();
  if (!request.url().includes('/graphql') || request.method() !== 'POST') return;
  const work = (async () => {
    const sent = request.postDataJSON();
    const body = await response.json().catch(() => ({}));
    operations.push({ name: sent.operationName, errors: body.errors });
    if (body.data?.beaconCreate?.id) ids.add(body.data.beaconCreate.id);
  })();
  pending.add(work);
  work.finally(() => pending.delete(work));
});
const type = async (name, value) => {
  const field = page.getByRole('textbox', { name });
  await field.click();
  await page.waitForTimeout(400);
  await page.keyboard.type(value, { delay: 40 });
  assert.equal(await field.inputValue(), value, 'Valid form input prerequisite');
};
const calendarDay = async (label) => {
  const day = page.getByRole('button', { name: label });
  for (let attempt = 0; attempt < 8 && !await day.count(); attempt++) {
    await page.mouse.move(190, 450);
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(300);
  }
  await day.click();
};

try {
  const login = await context.request.post(`${base}/api/v2/auth/email/test-login`, {
    data: { email: process.env.E2E_EMAIL || 'alice.fz1106@test.tentura.local' },
  });
  assert.ok(login.ok(), 'QA login prerequisite');
  await page.goto(`${base}/?lang=en#/beacon/new`);
  await page.locator('flt-semantics').first().waitFor({ state: 'attached', timeout: 60000 });
  await type(/What do you need/i, 'ValidRequest');
  await type(/Describe what you need/i, 'FindSupplies');
  await page.getByRole('button', { name: /^When\?/ }).click();
  await page.getByText('Date / period', { exact: true }).first().click();
  await page.getByRole('button', { name: /Date \/ period.*Tap to choose/s }).click();
  await calendarDay(/December 30, 2026/);
  await calendarDay(/December 31, 2026/);
  await page.getByRole('button', { name: 'OK', exact: true }).click();
  await page.waitForTimeout(400);
  await page.getByRole('button', { name: 'OK', exact: true }).click();
  await page.getByRole('button', { name: /^Requirements/ }).click();
  await page.getByRole('button', { name: /^Transport,/ }).click();
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.getByRole('button', { name: 'Next: Recipients', exact: true }).click();
  await page.getByRole('button', { name: /Publish without sending/i }).waitFor();
  await Promise.all([...pending]);
  assert.ok(ids.size > 0, `Recipients has a saved draft id: ${JSON.stringify(operations)}`);
  assert.equal(await page.getByText(/Couldn't prepare the draft/).count(), 0);
  const auth = await context.request.post(`${base}/api/v2/session/access-token`);
  const { access_token: token } = await auth.json();
  const response = await context.request.post(`${base}/api/v1/graphql`, {
    headers: { Authorization: `Bearer ${token}` },
    data: {
      query: 'query SavedDraft($id: String!) { beacon_by_pk(id: $id) { id title description status needs primary_need_slug start_at end_at } }',
      variables: { id: [...ids].at(-1) },
    },
  });
  const saved = await response.json();
  assert.ok(!saved.errors?.length, JSON.stringify(saved.errors));
  const draft = saved.data.beacon_by_pk;
  assert.equal(draft.title, 'ValidRequest');
  assert.equal(draft.description, 'FindSupplies');
  assert.equal(draft.status, 3);
  assert.equal(draft.needs, 'transport');
  assert.equal(draft.primary_need_slug, 'transport');
  assert.equal(new Date(draft.start_at).toISOString(), '2026-12-29T23:00:00.000Z');
  assert.equal(new Date(draft.end_at).toISOString(), '2026-12-30T23:00:00.000Z');
  console.log('PASS: full When range and Transport reach Recipients with a saved draft id');
} catch (error) {
  console.error(JSON.stringify({ operations, controls: await page.locator('[role="button"]').evaluateAll(
    (nodes) => nodes.map((node) => node.getAttribute('aria-label') || node.textContent).slice(0, 45),
  ) }));
  throw error;
} finally {
  await Promise.all([...pending]);
  if (ids.size) {
    const auth = await context.request.post(`${base}/api/v2/session/access-token`);
    const { access_token: token } = await auth.json();
    for (const id of ids) {
      const response = await context.request.post(`${base}/api/v2/graphql`, {
        headers: { Authorization: `Bearer ${token}` },
        data: {
          query: 'mutation DeleteDraft($id: String!) { beaconDeleteById(id: $id) }',
          variables: { id },
        },
      });
      const body = await response.json();
      assert.equal(body.data?.beaconDeleteById, true, 'Remove only this test draft');
    }
  }
  await context.request.post(`${base}/api/v2/session/logout`);
  await browser.close();
}
