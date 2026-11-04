// #741: typing survives the capability search's clear × and its tooltip in
// the Requirements sheet (request editor) and Edit labels (profile), with a
// real desktop mouse and keyboard on the authenticated application.
// Usage: node sheet_search_keeps_typing.mjs [cycles=10]
// Exit 2: typed keys were lost. Exit 1: a prerequisite failed (login,
// profile/Wasm app, sheet, labeled field/action). Exit 0: every checkpoint.
// Selectors are CapabilitySearchField's accessible names: the field's label
// (l10n capabilitySearchLabel) and the clear tooltip (capabilitySearchClear).
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.BASE || 'https://dev.lvh.me:9443';
const cycles = Number.parseInt(process.argv[2] || process.env.CYCLES || '10', 10);
const copy = {
  en: {
    requirements: /^Requirements/, edit: 'Edit labels', save: 'Save',
    search: 'Search', clear: 'Clear search',
  },
  ru: {
    requirements: /^Требования/, edit: 'Изменить метки', save: 'Сохранить',
    search: 'Поиск', clear: 'Очистить поиск',
  },
};
const locales = (process.env.LOCALES || 'en,ru').split(',');
const surfaces = (process.env.SURFACES || 'Requirements,Edit labels').split(',');
const modes = (process.env.MODES || 'close,hover').split(',');
assert.ok(cycles > 0, 'cycles must be a positive integer');

const results = [];
const browser = await chromium.launch({
  channel: 'chrome', headless: process.env.HEADLESS !== '0', args: ['--no-sandbox'],
});
try {
  for (const locale of locales) {
    for (const surface of surfaces) {
      for (const mode of modes) {
        const name = `${surface} search keeps typing through ${mode} with desktop mouse (${locale})`;
        const context = await browser.newContext({
          ignoreHTTPSErrors: true, serviceWorkers: 'block',
          viewport: { width: 1280, height: 800 }, locale: `${locale}-${locale === 'en' ? 'US' : 'RU'}`,
        });
        let sheetOpened = false;
        try {
          const login = await context.request.post(`${base}/api/v2/auth/email/test-login`, {
            data: { email: process.env.EMAIL || 'society-bravo3@test.tentura.local' },
          });
          assert.ok(login.ok(), `QA login prerequisite: HTTP ${login.status()}`);
          const page = await context.newPage();
          page.setDefaultTimeout(15000);
          let wasmLoaded = false;
          page.on('response', response => {
            if (new URL(response.url()).pathname.endsWith('/main.dart.wasm') && response.ok()) wasmLoaded = true;
          });
          const route = surface === 'Requirements' ? '/beacon/new' : '/home/network';
          await page.goto(`${base}/?lang=${locale}#${route}`);
          if (surface === 'Requirements') {
            await page.getByRole('button', { name: copy[locale].requirements }).click();
          } else {
            // A real trusted contact from the shared society QA dataset.
            const contact = page.getByRole('group', { name: /society author/ });
            await contact.waitFor({ state: 'visible' });
            const box = await contact.boundingBox();
            assert.ok(box, 'Visible trusted contact prerequisite');
            await page.mouse.click(Math.round(box.x + 70), Math.round(box.y + box.height / 2));
            await page.getByRole('button', { name: copy[locale].edit, exact: true }).click();
          }
          await page.getByRole('button', { name: copy[locale].save, exact: true }).waitFor();
          assert.ok(wasmLoaded, 'Serve a freshly built profile/Wasm application');
          assert.equal(await page.evaluate(() => crossOriginIsolated), true, 'Deployment isolation headers');
          sheetOpened = true;

          // Only the modal remains in the accessibility tree; the label is
          // CapabilitySearchField's own (capabilitySearchLabel).
          const field = page.getByRole('textbox', { name: copy[locale].search, exact: true });
          await page.waitForTimeout(500);
          assert.equal(await field.count(), 1,
            `${surface} must offer one search textbox labeled «${copy[locale].search}»`);
          // The clear action stays mounted (disabled) while the field is
          // empty, so it is found by its tooltip label from the start.
          const clear = page.getByRole('button', { name: copy[locale].clear, exact: true });
          assert.equal(await clear.count(), 1,
            `${surface} search must offer one clear action labeled «${copy[locale].clear}»`);
          const label = copy[locale].clear;

          const expectValue = async (expected, checkpoint) => {
            for (let retry = 0; retry < 20 && await field.inputValue() !== expected; retry++) {
              await page.waitForTimeout(100);
            }
            assert.equal(await field.inputValue(), expected, checkpoint);
          };
          const tooltipVisible = async (text, visible = true) => page.waitForFunction(({ text, visible }) =>
            [...document.querySelectorAll('flt-semantics')].some(element => {
              if (element.closest('[role="button"]') || element.querySelector('[role="button"]')) return false;
              if (element.textContent?.trim() !== text && element.getAttribute('aria-label') !== text) return false;
              const box = element.getBoundingClientRect();
              return box.width > 0 && box.height > 0 && getComputedStyle(element).visibility !== 'hidden';
            }) === visible, { text, visible }, { timeout: 5000 });
          const failures = [];
          for (let cycle = 1; cycle <= cycles; cycle++) {
            await field.click();
            // The engine attaches its editing element asynchronously after a
            // pointer focus.
            await page.waitForTimeout(400);
            await page.keyboard.press('ControlOrMeta+A');
            await page.keyboard.type('Bo', { delay: 80 });
            await expectValue('Bo', `Cycle ${cycle}: initial typing reaches search`);
            await clear.hover();
            await tooltipVisible(label);
            if (mode === 'close') {
              const box = await clear.boundingBox();
              assert.ok(box, 'Clear action has a box');
              await page.mouse.click(Math.round(box.x + box.width / 2), Math.round(box.y + box.height / 2));
              await expectValue('', `Cycle ${cycle}: clear removes query`);
              // Leave the pointer exactly at the clear action, with no field
              // click, DOM focus(), value assignment, or synthetic blur.
              await page.waitForTimeout(1500);
              await tooltipVisible(label);
            }
            await page.keyboard.type('Zz', { delay: 80 });
            const expected = mode === 'close' ? 'Zz' : 'BoZz';
            await page.waitForTimeout(400);
            const actual = await field.inputValue();
            console.log(JSON.stringify({ name, cycle, expected, actual }));
            if (actual !== expected) failures.push({ cycle, expected, actual });
            // Hover mode also proves typing survives the tooltip disappearing.
            if (mode === 'hover') {
              await page.mouse.move(1270, 790);
              await page.waitForTimeout(1500);
              await tooltipVisible(label, false);
              await page.keyboard.type('Yy', { delay: 80 });
              await page.waitForTimeout(400);
              const afterHide = await field.inputValue();
              if (afterHide !== 'BoZzYy') failures.push({ cycle, expected: 'BoZzYy', actual: afterHide });
            }
          }
          assert.deepEqual(failures, [], `Every checkpoint in all ${cycles} cycles preserves typed text`);
          results.push({ name, exitCode: 0 });
        } catch (error) {
          // Setup failures cannot masquerade as acceptance evidence.
          const exitCode = sheetOpened && error instanceof assert.AssertionError ? 2 : 1;
          results.push({ name, exitCode, error: error.message });
          console.error(`${exitCode === 2 ? 'FAIL' : 'SETUP ERROR'} ${name}: ${error.message}`);
        } finally {
          await context.close();
        }
      }
    }
  }
} finally {
  await browser.close();
}
console.log('ACCEPTANCE MATRIX', JSON.stringify(results));
process.exitCode = results.some(row => row.exitCode === 1) ? 1 : results.some(row => row.exitCode === 2) ? 2 : 0;
