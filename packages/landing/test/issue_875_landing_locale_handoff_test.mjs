// #875: explicit landing ?lang= must reach the Flutter app on hand-off.
import assert from 'node:assert/strict';
import test from 'node:test';

test('withAppLocaleHandoff adds lang=ru when the visit started with ?lang=ru', async () => {
  const { initLocale, withAppLocaleHandoff } = await import('../onboarding.js');
  initLocale({ location: { search: '?lang=ru' }, languages: ['en-US'] });
  const out = withAppLocaleHandoff('https://app.test/');
  const url = new URL(out);
  assert.equal(url.searchParams.get('lang'), 'ru');
});

test('withAppLocaleHandoff leaves the app URL unchanged for browser-only Russian', async () => {
  const { initLocale, withAppLocaleHandoff } = await import('../onboarding.js');
  initLocale({ location: { search: '' }, languages: ['ru-RU', 'ru'] });
  assert.equal(withAppLocaleHandoff('https://app.test/'), 'https://app.test/');
});

test('withAppLocaleHandoff adds lang=en for an explicit English choice', async () => {
  const { initLocale, withAppLocaleHandoff } = await import('../onboarding.js');
  initLocale({ location: { search: '?lang=en' }, languages: ['ru-RU'] });
  const url = new URL(withAppLocaleHandoff('https://app.test/'));
  assert.equal(url.searchParams.get('lang'), 'en');
});

test('main openProductUrl uses withAppLocaleHandoff', async () => {
  const { readFileSync } = await import('node:fs');
  const mainJs = readFileSync(new URL('../main.js', import.meta.url), 'utf8');
  assert.match(mainJs, /withAppLocaleHandoff\(`\$\{location\.origin\}\/`\)/);
});
