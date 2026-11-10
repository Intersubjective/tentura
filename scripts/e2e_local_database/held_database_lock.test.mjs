// Another tab (frozen or in the background) holds the local database's
// cross-tab lock `tentura:local-db:main_db` while this tab boots. The
// production opener must wait for the lock only for a bounded time, ask again,
// and then give up with a lock error before the 60 s boot timeout. Each stage
// of the open (probe, lock wait, open, import) leaves a `local_db` Sentry
// breadcrumb, so a report shows where boot stopped.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { browser, pageIn, call, seedLegacy } from './browser_fixture.mjs';

const lockName = 'tentura:local-db:main_db';
const bootTimeoutMs = 60000;
// Under the boot timeout: the lock error must beat the generic boot failure.
const heldLockBoundMs = bootTimeoutMs - 1000;

// Counts this page's requests for the database lock.
function countLockRequests() {
  const original = LockManager.prototype.request;
  globalThis.__localDbLockRequests = 0;
  LockManager.prototype.request = function (name, ...rest) {
    if (String(name) === 'tentura:local-db:main_db') globalThis.__localDbLockRequests++;
    return original.call(this, name, ...rest);
  };
}

async function lockRequests(page) {
  return page.evaluate(() => globalThis.__localDbLockRequests);
}

// Holds the lock in another tab until release() — or forever.
async function holdLock(context) {
  const holder = await pageIn(context);
  await holder.evaluate((name) => new Promise((granted) => {
    navigator.locks.request(name, () => {
      granted();
      return new Promise((release) => { globalThis.__releaseDatabaseLock = release; });
    });
  }), lockName);
  return {
    release: () => holder.evaluate(() => globalThis.__releaseDatabaseLock()),
  };
}

// Starts the production open (the boot auth_accounts query) without awaiting it.
function startOpen(page) {
  const started = Date.now();
  const result = page.evaluate(
    async () => JSON.parse(await window.localDatabaseCall(JSON.stringify({ operation: 'open' }))),
  );
  return { started, result };
}

async function within(promise, ms, what) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${what} did not finish within ${ms} ms`)), ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function until(condition, ms, what) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (await condition()) return;
    await new Promise((tick) => setTimeout(tick, 50));
  }
  throw new Error(`${what} did not happen within ${ms} ms`);
}

// Stage breadcrumbs, in the `local_db:<stage>` style of
// local_db:storage_selected. One message per stage, so a report's last stage
// breadcrumb says where the open stopped.
const STAGES = [
  'local_db:probe_started',
  'local_db:probe_finished',
  'local_db:lock_wait_started',
  'local_db:lock_acquired',
  'local_db:open_finished',
  'local_db:import_started',
  'local_db:import_finished',
];

async function localDbCrumbs(page) {
  const { breadcrumbs } = await call(page, 'telemetry');
  return breadcrumbs.filter((crumb) => crumb.category === 'local_db');
}

function stageTrail(crumbs) {
  return crumbs.filter((crumb) => STAGES.includes(crumb.message));
}

function stageNames(crumbs) {
  return stageTrail(crumbs).map((crumb) => crumb.message.slice('local_db:'.length));
}

async function seededProfile(context) {
  const page = await pageIn(context);
  await call(page, 'open');
  const fixture = await call(page, 'seed');
  await call(page, 'close');
  await page.close();
  return fixture.map(({ id, displayName }) => ({ id, displayName }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

describe('local database cross-tab lock and open stage breadcrumbs', () => {
  test('with no other lock holder the first lock request opens the database, lists the accounts and breadcrumbs every stage', { timeout: 180000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    await context.addInitScript(countLockRequests);
    const accounts = await seededProfile(context);

    const page = await pageIn(context);
    await call(page, 'open');
    assert.equal(await lockRequests(page), 1, 'An uncontended open asks for the lock once');
    const snapshot = await call(page, 'snapshot');
    snapshot.accounts.sort((a, b) => a.id.localeCompare(b.id));
    assert.deepEqual(snapshot.accounts, accounts);

    const crumbs = await localDbCrumbs(page);
    const order = stageNames(crumbs);
    // The read-only probe runs before the lock is requested; the open
    // finishes last, inside the lock.
    assert.deepEqual(
      order,
      ['probe_started', 'probe_finished', 'lock_wait_started', 'lock_acquired', 'open_finished'],
      'stage breadcrumbs of an uncontended open',
    );
    const acquired = stageTrail(crumbs).find((crumb) => crumb.message === 'local_db:lock_acquired');
    assert.ok(Number.isInteger(acquired.data?.wait_ms) && acquired.data.wait_ms >= 0,
      `lock_acquired carries the lock wait as data.wait_ms: ${JSON.stringify(acquired.data)}`);
  });

  test('importing a legacy OPFS database leaves import started and finished breadcrumbs', { timeout: 180000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    await seedLegacy(context);
    const page = await pageIn(context);
    await call(page, 'open');
    const order = stageNames(await localDbCrumbs(page));
    assert.equal(order.filter((stage) => stage === 'import_started').length, 1, `import started: ${JSON.stringify(order)}`);
    assert.equal(order.filter((stage) => stage === 'import_finished').length, 1, `import finished: ${JSON.stringify(order)}`);
    assert.ok(order.indexOf('import_started') < order.indexOf('import_finished'), JSON.stringify(order));
    assert.equal(order.at(-1), 'open_finished', JSON.stringify(order));
  });

  test('a lock held forever by another tab ends the open with a lock error before the boot timeout, after asking again, and the breadcrumbs stop at the lock wait', { timeout: 180000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    await context.addInitScript(countLockRequests);
    await holdLock(context);

    const page = await pageIn(context);
    const open = startOpen(page);
    const outcome = await within(open.result, heldLockBoundMs, 'The open behind a held lock');
    const elapsed = Date.now() - open.started;

    assert.equal(outcome.ok, false, 'The open cannot succeed while another tab holds the lock');
    assert.ok(elapsed < bootTimeoutMs, `gave up after ${elapsed} ms`);
    // The harness returns error.toString(). Like LocalDatabaseOpenException
    // and LocalDatabaseClosedException, the lock-held error prints its own
    // type name first (a string, so it survives the minified --wasm build);
    // a reopen failure prints it as its cause.
    assert.match(outcome.error, /^(LocalDatabaseOpenException: .*: )?LocalDatabaseLockHeldException: /s,
      'The open fails with the distinct lock-held error');
    assert.doesNotMatch(outcome.error, /BootTimeoutException|Startup step not completed/);
    assert.ok(await lockRequests(page) >= 2, 'The opener asks for the lock again before giving up');

    const crumbs = await localDbCrumbs(page);
    const order = stageNames(crumbs);
    const messages = JSON.stringify(crumbs.map((crumb) => crumb.message));
    assert.ok(order.filter((stage) => stage === 'lock_wait_started').length >= 2,
      `one lock_wait_started per attempt, at least two: ${messages}`);
    assert.equal(order.includes('lock_acquired'), false, `the lock was never acquired: ${messages}`);
    assert.equal(order.includes('open_finished'), false, messages);
    assert.equal(order.at(-1), 'lock_wait_started', `the last stage breadcrumb is the lock wait: ${messages}`);
  });

  test('when the other tab releases the lock during the retries the open completes and lists the stored accounts', { timeout: 180000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    await context.addInitScript(countLockRequests);
    const accounts = await seededProfile(context);
    const holder = await holdLock(context);

    const page = await pageIn(context);
    const open = startOpen(page);
    // The first bounded wait has timed out once the lock is requested again.
    await until(async () => (await lockRequests(page)) >= 2, heldLockBoundMs,
      'A second lock request after the first bounded wait');
    await holder.release();

    const outcome = await within(open.result, bootTimeoutMs, 'The open after the lock was released');
    assert.equal(outcome.ok, true, `The retry after release must open: ${outcome.error || ''}`);
    const snapshot = await call(page, 'snapshot');
    snapshot.accounts.sort((a, b) => a.id.localeCompare(b.id));
    assert.deepEqual(snapshot.accounts, accounts);
  });

  test('a probe that never completes leaves probe started as the last stage breadcrumb', { timeout: 180000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    const page = await pageIn(context);
    // From now on the database worker and SQLite never arrive: the probe stalls.
    await context.route(/\/assets\/packages\/(sqlite3\.wasm|drift_worker\.js)$/, () => {});
    let settled = false;
    startOpen(page).result.finally(() => { settled = true; }).catch(() => {});
    await new Promise((wait) => setTimeout(wait, 5000));
    assert.equal(settled, false, 'Precondition: with its worker and SQLite blocked the probe must stall, not fail');

    const crumbs = await localDbCrumbs(page);
    const order = stageNames(crumbs);
    const messages = JSON.stringify(crumbs.map((crumb) => crumb.message));
    assert.ok(order.includes('probe_started'), `probe started: ${messages}`);
    assert.equal(order.includes('probe_finished'), false, `the probe never finished: ${messages}`);
    assert.equal(order.at(-1), 'probe_started', `the last stage breadcrumb is the probe: ${messages}`);
  });
});
