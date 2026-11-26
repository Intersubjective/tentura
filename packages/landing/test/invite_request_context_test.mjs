import assert from 'node:assert/strict';
import test from 'node:test';

import { renderLanding } from './landing_browser_fake.mjs';

const origin = 'https://tentura.test';
const code = 'Iabc123';
const invitePath = `/invite/${code}`;
const previewPath = `/api/v2${invitePath}/preview`;
// Reserved characters make a lost or double URL encoding observable.
const requestId = 'Brequest+one&two#three';
const requestQuery = `r=${encodeURIComponent(requestId)}`;
const contexts = [
  { name: 'without-context', search: '', expected: null },
  { name: 'empty-context', search: '?r=', expected: null },
  { name: 'with-context', search: `?${requestQuery}`, expected: requestId },
];
const anonymous = {
  codeStatus: 'available',
  callerStatus: 'anonymous',
  suggestedAction: 'accept-as-new',
  inviter: { id: 'U1', displayName: 'Morgan' },
  phantomInvite: true,
};
const existing = {
  ...anonymous,
  callerStatus: 'existing-user',
  suggestedAction: 'accept-as-existing',
};

function visibleControl(card, tag, label) {
  const matches = card.querySelectorAll(tag).filter(
    (node) => node.textContent === label && node.isShownIn(card),
  );
  assert.equal(matches.length, 1, `expected one visible control labelled ${label}`);
  return matches[0];
}

function linkUrl(card, label) {
  const href = visibleControl(card, 'a', label).getAttribute('href');
  assert.ok(href, `expected a destination for ${label}`);
  return new URL(href, origin);
}

test('invite preview fetches the encoded Request context when present', async () => {
  for (const { name, search, expected } of contexts) {
    const requests = [];
    await renderLanding({
      pathname: invitePath,
      search,
      fetchResponse: async (url) => {
        if (url === '/wasm-preload-manifest.json') {
          return { ok: false, status: 404 };
        }
        requests.push(new URL(url, origin));
        return { ok: true, status: 200, json: async () => anonymous };
      },
    }, `request-preview-${name}`);

    assert.equal(requests.length, 1, name);
    const [url] = requests;
    assert.equal(url.origin, origin, name);
    assert.equal(url.pathname, previewPath, name);
    assert.equal(url.hash, '', name);
    assert.deepEqual([...url.searchParams], expected === null ? [] : [['r', expected]], name);
  }
});

test('opening Tentura carries Request context in the invite route and preserves the chosen language', async () => {
  for (const { name, search, expected } of contexts) {
    const hasLocale = expected !== null;
    const card = await renderLanding({
      pathname: invitePath,
      search: hasLocale ? `${search}&lang=ru` : search,
      preview: existing,
    }, `request-app-${name}`);
    const href = linkUrl(card, hasLocale ? 'Открыть Tentura и принять' : 'Open Tentura to accept');
    const route = new URL(href.hash.slice(1), origin);

    assert.equal(href.origin, origin, name);
    assert.equal(href.pathname, '/', name);
    assert.deepEqual([...href.searchParams], hasLocale ? [['lang', 'ru']] : [], name);
    assert.equal(route.pathname, `/accept-invite/${code}`, name);
    assert.equal(route.hash, '', name);
    assert.deepEqual([...route.searchParams], expected === null ? [] : [['r', expected]], name);
  }
});

test('seed recovery keeps the Request context alongside the invite code', async () => {
  for (const { name, search, expected } of contexts) {
    const card = await renderLanding({
      pathname: invitePath,
      search,
      preview: anonymous,
    }, `request-recover-${name}`);
    const label = 'I already have an account';
    visibleControl(card, 'button', label).click();
    const href = linkUrl(card, label);

    assert.equal(href.origin, origin, name);
    assert.equal(href.pathname, '/recover', name);
    assert.equal(href.hash, '#/recover-seed', name);
    assert.equal(href.searchParams.get('invite'), code, name);
    assert.match(href.searchParams.get('auth_attempt_id') ?? '', /^S[0-9a-f]+$/, name);
    assert.deepEqual(href.searchParams.getAll('r'), expected === null ? [] : [expected], name);
  }
});

test('the Google sign-in return URL keeps the invite and its Request context', async () => {
  for (const { name, search, expected } of contexts) {
    const card = await renderLanding({
      pathname: invitePath,
      search,
      preview: anonymous,
    }, `request-google-${name}`);
    const href = linkUrl(card, 'Continue with Google');
    assert.equal(href.origin, origin, name);
    assert.equal(href.pathname, '/api/auth/google/start', name);
    assert.equal(href.searchParams.get('invite'), code, name);
    const attempt = href.searchParams.get('auth_attempt_id');
    assert.match(attempt ?? '', /^G[0-9a-f]+$/, name);
    const returned = new URL(href.searchParams.get('returnTo'));

    assert.equal(returned.origin, origin, name);
    assert.equal(returned.pathname, invitePath, name);
    assert.equal(returned.hash, '', name);
    assert.equal(returned.searchParams.get('auth_attempt_id'), attempt, name);
    assert.deepEqual(returned.searchParams.getAll('r'), expected === null ? [] : [expected], name);
  }
});
