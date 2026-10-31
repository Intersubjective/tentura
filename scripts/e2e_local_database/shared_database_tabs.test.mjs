import assert from 'node:assert/strict';
import { test } from 'node:test';
import { browser, pageIn, response, call, hasDatabase } from './browser_fixture.mjs';

test('two tabs share committed contacts and settings through fifteen concurrent rounds and survive the first tab closing', { timeout: 240000 }, async (t) => {
  const context = await browser.newContext();
  t.after(() => context.close());
  const first = await pageIn(context);
  await call(first, 'open');
  const fixture = await call(first, 'seed');
  const second = await pageIn(context);
  await call(second, 'open');
  const failures = [];
  for (let round = 0; round < 15; round++) {
    const outcomes = await Promise.all([
      response(first, 'contacts', { round }),
      response(second, 'settingsAndAccounts', { round }),
    ]);
    for (const [index, outcome] of outcomes.entries()) {
      if (!outcome.ok) failures.push({ round, tab: index + 1, error: outcome.error });
    }
    // Always read from both tabs after awaiting this round's writes, even if
    // an operation failed. No failed round can silently skip visibility checks.
    const states = await Promise.all([
      response(first, 'roundState'),
      response(second, 'roundState'),
    ]);
    const expected = {
      contacts: Object.fromEntries(Array.from({ length: 50 }, (_, i) => [
        `subject-${i}`, `round-${round}-contact-${i}-${'name'.repeat(20)}`,
      ])),
      appId: `round-${round}`,
      intro: round % 2 === 0,
      accounts: fixture.map((account, i) => ({
        id: account.id,
        displayName: i === 0 ? `Owner ${round}` : account.displayName,
      })).sort((a, b) => a.id.localeCompare(b.id)),
    };
    for (const [index, state] of states.entries()) {
      try {
        assert.equal(state.ok, true, `Tab ${index + 1} must read committed round ${round}: ${state.error || ''}`);
        state.value.accounts.sort((a, b) => a.id.localeCompare(b.id));
        assert.deepEqual(state.value, expected, `Tab ${index + 1} must see contacts written by tab 1 and appId, intro and account name written by tab 2 in round ${round}`);
      } catch (error) {
        failures.push({ round, tab: index + 1, error: error.message });
      }
    }
  }
  assert.deepEqual(failures, [], 'All fifteen rounds must commit without SqliteException');
  await first.close(); // Abrupt browser close, not a cooperative database close.
  assert.equal((await call(second, 'snapshot')).accounts.length, 2);
  await call(second, 'settingsAndAccounts', { round: 15 });
  await call(second, 'contacts', { round: 15 });
  assert.equal(await call(second, 'readAppId'), 'round-15');
  const survivingState = await call(second, 'roundState');
  assert.deepEqual(survivingState.contacts, Object.fromEntries(Array.from({ length: 50 }, (_, i) => [
    `subject-${i}`, `round-15-contact-${i}-${'name'.repeat(20)}`,
  ])), 'The surviving tab must still commit and read all contacts after the first tab closes');
  assert.equal(survivingState.appId, 'round-15');
  assert.equal(survivingState.intro, false);
  assert.equal(survivingState.accounts.find((account) => account.id === fixture[0].id).displayName, 'Owner 15');
  const inventory = await call(second, 'inventory');
  assert.equal(hasDatabase(inventory, 'indexedDb'), true, 'The shared database must persist in IndexedDB');
  assert.equal(hasDatabase(inventory, 'opfs'), false, 'New profiles must never open OPFS');
});
