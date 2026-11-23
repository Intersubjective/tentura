import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLanding } from './landing_browser_fake.mjs';

const handoffKey = 'tentura_post_join_beacon';
const request = { id: 'B1', title: 'Fix the roof', kind: 'request' };
const inviterName = 'Vadim';

function renderRequestInvite({ audience, lapse, tag = '' }) {
  const existing = audience === 'existing account';
  return renderLanding(
    {
      pathname: '/invite/Iabc123',
      preview: {
        codeStatus: 'available',
        callerStatus: existing ? 'existing-user' : 'anonymous',
        suggestedAction: existing ? 'accept-as-existing' : 'accept-as-new',
        inviter: { displayName: inviterName },
        beacon: { ...request, ...(lapse === undefined ? {} : { lapsed: lapse }) },
      },
    },
    `request-handoff-${audience}-${lapse}-${tag}`,
  );
}

for (const audience of ['new account', 'existing account']) {
  const account = audience === 'new account' ? 'a new account' : 'an existing account';
  test(`a closed Request invite leaves no app handoff for ${account}`, async () => {
    const card = await renderRequestInvite({ audience, lapse: true });

    assert.match(card.textContent, /Vadim invited you to «Fix the roof», but it has already closed\./);
    if (audience === 'new account') {
      assert.match(card.textContent, /You're still welcome on Tentura, and you're now connected with Vadim\./);
      assert.ok(card.querySelector('#email-signin')?.isShownIn(card), 'email signup is visible');
    }

    assert.equal(sessionStorage.getItem(handoffKey), null);
  });
}

for (const [description, audience, lapse] of [
  ['an open Request invite for a new account', 'new account', false],
  ['an open Request invite for an existing account', 'existing account', false],
  ['a Request invite from a server without lapse information', 'new account', undefined],
]) {
  test(`${description} saves the Request and inviter for the app`, async () => {
    await renderRequestInvite({ audience, lapse });

    assert.deepEqual(JSON.parse(sessionStorage.getItem(handoffKey)), {
      ...request,
      inviterName,
    });
  });
}

test('email signup retains the Request handoff only while the Request remains open', async () => {
  const expectedHandoff = { ...request, inviterName };
  const outcomes = [];
  for (const requestLapsed of [false, true]) {
    const preview = await renderRequestInvite({
      audience: 'new account',
      lapse: false,
      tag: `email-return-${requestLapsed}`,
    });
    assert.ok(preview.querySelector('#email-signin')?.isShownIn(preview));
    const storage = sessionStorage;
    assert.deepEqual(JSON.parse(storage.getItem(handoffKey)), expectedHandoff);

    // Follow the email verification redirect in the original tab.
    const requests = [];
    await renderLanding(
      {
        pathname: '/invite/Iabc123',
        search: `?signed_in=1&new=1&requestLapsed=${requestLapsed}`,
        storage,
        fetchResponse: async (url) => {
          if (url === '/wasm-preload-manifest.json') {
            return { ok: false, status: 404 };
          }
          requests.push(url);
          return {
            ok: true,
            status: 200,
            json: async () => ({ id: 'Ujoiner', displayName: 'New member' }),
          };
        },
      },
      `request-handoff-email-return-${requestLapsed}`,
    );
    assert.deepEqual(requests, ['/api/v2/accounts/me/profile']);
    const stored = storage.getItem(handoffKey);
    outcomes.push(requestLapsed ? stored : JSON.parse(stored));
  }

  assert.deepEqual(outcomes, [expectedHandoff, null]);
});
