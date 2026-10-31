import assert from 'node:assert/strict';
import { test } from 'node:test';
import { browser, pageIn, response, call, hasDatabase, seedLegacy } from './browser_fixture.mjs';

test('an existing OPFS profile keeps its accounts and settings in IndexedDB and retires the OPFS copy after opening', { timeout: 180000 }, async (t) => {
  const context = await browser.newContext();
  t.after(() => context.close());
  const { fixture, snapshot } = await seedLegacy(context);
  const page = await pageIn(context);
  // Hold the legacy-byte read that initializes the new database. This checks
  // that the source survives while the production open is still unfinished.
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const directory = await (await root.getDirectoryHandle('drift_db')).getDirectoryHandle('main_db');
    const legacy = await directory.getFileHandle('database');
    const getFile = FileSystemFileHandle.prototype.getFile;
    window.localDatabaseImportHeld = false;
    window.localDatabaseImportReads = 0;
    FileSystemFileHandle.prototype.getFile = async function (...args) {
      const file = await getFile.apply(this, args);
      if (await this.isSameEntry(legacy)) {
        const arrayBuffer = file.arrayBuffer.bind(file);
        Object.defineProperty(file, 'arrayBuffer', {
          value: async () => {
            const bytes = await arrayBuffer();
            window.localDatabaseImportReads++;
            await new Promise((release) => {
              window.localDatabaseImportRelease = release;
              window.localDatabaseImportHeld = true;
            });
            return bytes;
          },
        });
      }
      return file;
    };
  });
  let openSettled = false;
  const opening = response(page, 'open').then((result) => {
    openSettled = true;
    return result;
  });
  const held = await page.waitForFunction(() => window.localDatabaseImportHeld, null, { timeout: 5000 }).then(() => true, () => false);
  assert.equal(held, true, 'The production opener must read the legacy OPFS bytes to initialize IndexedDB');
  assert.equal(openSettled, false, 'The new database must not finish opening before import initialization completes');
  const sourceStillExists = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    try {
      const directory = await (await root.getDirectoryHandle('drift_db')).getDirectoryHandle('main_db');
      await directory.getFileHandle('database');
      return true;
    } catch (error) {
      if (error.name === 'NotFoundError') return false;
      throw error;
    }
  });
  assert.equal(sourceStillExists, true, 'OPFS must remain intact while the imported database has not opened successfully');
  assert.equal(await page.evaluate(() => window.localDatabaseImportReads), 1);
  await page.evaluate(() => window.localDatabaseImportRelease());
  const opened = await opening;
  assert.equal(opened.ok, true, `The imported database must open successfully: ${opened.error || ''}`);
  assert.deepEqual(await call(page, 'snapshot'), snapshot, 'Account names and all stored preferences must survive');
  assert.deepEqual(await call(page, 'seeds'), Object.fromEntries(fixture.map((account) => [account.id, account.seed])));
  const inventory = await call(page, 'inventory');
  assert.equal(hasDatabase(inventory, 'opfs'), false, 'Delete OPFS only after the imported database opens successfully');
  assert.equal(hasDatabase(inventory, 'indexedDb'), true);
  await call(page, 'close');
  await page.close();
  const reopened = await pageIn(context);
  await call(reopened, 'open');
  assert.deepEqual(await call(reopened, 'snapshot'), snapshot, 'Carry-over must persist across a fresh tab');
});

