// #802: QA test-login 400 copy is translated; post-sign-in redirects keep ?lang=ru.
import test from 'node:test';
import assert from 'node:assert/strict';

globalThis.window = globalThis;
globalThis.TENTURA = { apiBase: '' };

const storage = new Map();
globalThis.sessionStorage = {
  getItem: (k) => storage.get(k) ?? null,
  setItem: (k, v) => storage.set(k, v),
  removeItem: (k) => storage.delete(k),
};

function respond(status, body = {}) {
  globalThis.fetch = async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

async function rejection(promise) {
  try {
    await promise;
  } catch (err) {
    return err;
  }
  assert.fail('expected a rejection');
}

test('a 400 from QA test login shows Russian when ?lang=ru', async () => {
  const { initLocale, setLocale } = await import('../onboarding.js');
  initLocale({ search: '?lang=ru', languages: ['en-US'] });
  setLocale('ru');
  const { startTestLogin } = await import('../auth.js');
  respond(400, { error: 'domain_not_allowed' });
  const err = await rejection(startTestLogin({ email: 'u@example.com' }));
  assert.equal(
    err.message,
    'Тестовый вход не удался. Проверьте домен почты и попробуйте ещё раз.',
  );
});

test('withPreservedLocale adds lang=ru to a post-sign-in redirect URL', async () => {
  const { initLocale, setLocale, withPreservedLocale } = await import(
    '../onboarding.js'
  );
  initLocale({ search: '?lang=ru', languages: ['en-US'] });
  setLocale('ru');
  const out = withPreservedLocale(
    'https://dev.tentura.io/invite/Iabc?signed_in=1&new=1',
  );
  const url = new URL(out);
  assert.equal(url.searchParams.get('lang'), 'ru');
  assert.equal(url.searchParams.get('signed_in'), '1');
  assert.equal(url.searchParams.get('new'), '1');
});

test('withPreservedLocale leaves English URLs unchanged', async () => {
  const { initLocale, withPreservedLocale } = await import('../onboarding.js');
  initLocale({ search: '', languages: ['en-US'] });
  const href =
    'https://dev.tentura.io/invite/Iabc?signed_in=1&new=1';
  assert.equal(withPreservedLocale(href), href);
});
