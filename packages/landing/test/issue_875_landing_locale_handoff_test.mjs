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

test('withAppLocaleHandoff puts lang before the app route hash', async () => {
  const { initLocale, withAppLocaleHandoff } = await import('../onboarding.js');
  initLocale({ location: { search: '?lang=ru' }, languages: ['en-US'] });
  const url = new URL(withAppLocaleHandoff('https://app.test/#/accept-invite/ABC'));
  assert.equal(url.searchParams.get('lang'), 'ru');
  assert.equal(url.hash, '#/accept-invite/ABC');
});
