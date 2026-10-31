import assert from 'node:assert/strict';
import { test } from 'node:test';
import { browser, pageIn, response, call, hasDatabase, seedLegacy } from './browser_fixture.mjs';

test('a failed OPFS import restores every seed account without changing any secure-storage seed', { timeout: 180000 }, async (t) => {
  const context = await browser.newContext();
  t.after(() => context.close());
  const { fixture } = await seedLegacy(context);
  // Keep the legacy database valid. Fail only the production opener's attempt
  // to read that exact OPFS file for export/import, not general database reads.
  // Ignoring OPFS or treating it as absent cannot satisfy these observations.
  const page = await pageIn(context);
  const injectionControl = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const drift = await root.getDirectoryHandle('drift_db');
    const database = await drift.getDirectoryHandle('main_db');
    const legacy = await database.getFileHandle('database');
    const originalGetFile = FileSystemFileHandle.prototype.getFile;
    window.localDatabaseImportEvents = [];
    FileSystemFileHandle.prototype.getFile = async function (...args) {
      const file = await originalGetFile.apply(this, args);
      if (await this.isSameEntry(legacy)) {
        window.localDatabaseImportEvents.push({ phase: 'legacy-detected', database: 'main_db', source: 'opfs' });
        Object.defineProperty(file, 'arrayBuffer', {
          value: async () => {
            window.localDatabaseImportEvents.push({ phase: 'import-read-attempted' });
            const error = new DOMException('forced OPFS import read failure', 'NotReadableError');
            window.localDatabaseImportEvents.push({ phase: 'import-read-failed', error: error.message, name: error.name });
            throw error;
          },
        });
      }
      return file;
    };
    // Validate the fault injector, then clear the control observations. Only
    // accesses made by the subsequent production open can satisfy the test.
    let controlError;
    try {
      await (await legacy.getFile()).arrayBuffer();
    } catch (error) {
      controlError = { name: error.name, message: error.message };
    }
    window.localDatabaseImportEvents = [];
    return controlError;
  });
  assert.deepEqual(injectionControl, { name: 'NotReadableError', message: 'forced OPFS import read failure' });
  const opened = await response(page, 'open');
  const importEvents = await page.evaluate(() => window.localDatabaseImportEvents);
  const detected = importEvents.findIndex((event) => event.phase === 'legacy-detected' && event.source === 'opfs' && event.database === 'main_db');
  const attempted = importEvents.findIndex((event) => event.phase === 'import-read-attempted');
  const failed = importEvents.findIndex((event) => event.phase === 'import-read-failed' && event.name === 'NotReadableError' && event.error === 'forced OPFS import read failure');
  assert.ok(detected >= 0 && attempted > detected && failed > attempted,
    `The production opener must detect the legacy OPFS file and attempt its import before the injected read failure: ${JSON.stringify(importEvents)}`);
  assert.deepEqual(await call(page, 'seeds'), Object.fromEntries(fixture.map((account) => [account.id, account.seed])), 'Even a failed import must never delete or overwrite seeds');
  assert.equal(opened.ok, true, `A failed import must recover into an empty database: ${opened.error || ''}`);
  const recovered = await call(page, 'snapshot');
  assert.deepEqual(recovered.accounts.map((account) => account.id).sort(), fixture.map((account) => account.id).sort(), 'The account picker must still list every seed-backed account');
  await call(page, 'settingsAndAccounts', { round: 1 });
  const inventory = await call(page, 'inventory');
  assert.equal(hasDatabase(inventory, 'indexedDb'), true);
  await call(page, 'close');
  await page.close();
  const reopened = await pageIn(context);
  await call(reopened, 'open');
  assert.deepEqual(await call(reopened, 'seeds'), Object.fromEntries(fixture.map((account) => [account.id, account.seed])), 'Recovery must preserve every secure-storage seed across a fresh tab');
  assert.deepEqual((await call(reopened, 'snapshot')).accounts.map((account) => account.id).sort(), fixture.map((account) => account.id).sort(), 'Rebuilt account rows must persist rather than existing only in memory');
});
