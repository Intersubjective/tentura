import assert from 'node:assert/strict';
import { test } from 'node:test';
import { browser, pageIn, call, hasDatabase, assertModeTelemetry } from './browser_fixture.mjs';

test('without SharedWorker a single tab persists accounts and settings in unsafeIndexedDb', { timeout: 180000 }, async (t) => {
  const context = await browser.newContext();
  t.after(() => context.close());
  await context.addInitScript(() => { delete globalThis.SharedWorker; });
  const page = await pageIn(context);
  assert.equal(await page.evaluate(() => typeof SharedWorker), 'undefined');
  await call(page, 'open');
  const fixture = await call(page, 'seed');
  await call(page, 'contacts', { round: 0 });
  assert.deepEqual(await call(page, 'settingsAndAccounts', { round: 41 }), {
    appId: 'round-41', accounts: 2,
  });
  assert.equal(await call(page, 'readAppId'), 'round-41');
  const snapshot = await call(page, 'snapshot');
  assert.deepEqual(snapshot, {
    accounts: fixture.map((account, i) => ({
      id: account.id, displayName: i === 0 ? 'Owner 41' : account.displayName,
    })).sort((a, b) => a.id.localeCompare(b.id)),
    currentAccountId: fixture[0].id,
    theme: 'dark', locale: 'ru', intro: false,
  }, 'Without SharedWorker, account names and every preference must read back their committed values');
  assertModeTelemetry(await call(page, 'telemetry'), 'unsafeIndexedDb');
  const inventory = await call(page, 'inventory');
  assert.equal(inventory.available.includes('sharedIndexedDb'), false);
  assert.equal(inventory.available.includes('unsafeIndexedDb'), true);
  assert.equal(hasDatabase(inventory, 'indexedDb'), true, 'The Android-like fallback must use IndexedDB even when OPFS is available');
  assert.equal(hasDatabase(inventory, 'opfs'), false);
  await call(page, 'close');
  await page.close();
  const reopened = await pageIn(context);
  await call(reopened, 'open');
  assert.deepEqual(await call(reopened, 'snapshot'), snapshot);
  assert.equal(Object.keys(await call(reopened, 'readContacts')).length, 50);
  assert.equal(await call(reopened, 'readAppId'), 'round-41');
  assert.deepEqual(await call(reopened, 'settingsAndAccounts', { round: 42 }), {
    appId: 'round-42', accounts: 2,
  });
  const updated = await call(reopened, 'snapshot');
  assert.equal(updated.intro, true, 'The reopened fallback database must accept a new settings write');
  assert.equal(updated.accounts.find((account) => account.id === fixture[0].id).displayName, 'Owner 42');
  assert.equal(await call(reopened, 'readAppId'), 'round-42');
  assertModeTelemetry(await call(reopened, 'telemetry'), 'unsafeIndexedDb');
});
