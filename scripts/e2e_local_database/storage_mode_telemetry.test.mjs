import { test } from 'node:test';
import { browser, pageIn, call, assertModeTelemetry } from './browser_fixture.mjs';

for (const mode of ['sharedIndexedDb', 'unsafeIndexedDb']) {
  test(`the selected ${mode} storage is logged and breadcrumbed once during a session`, { timeout: 120000 }, async (t) => {
    const context = await browser.newContext();
    t.after(() => context.close());
    if (mode === 'unsafeIndexedDb') {
      await context.addInitScript(() => { delete globalThis.SharedWorker; });
    }
    const page = await pageIn(context);
    await call(page, 'open');
    await call(page, 'seed');
    for (let round = 0; round < 3; round++) {
      await call(page, 'settingsAndAccounts', { round });
      await call(page, 'snapshot');
    }
    assertModeTelemetry(await call(page, 'telemetry'), mode);
  });
}
