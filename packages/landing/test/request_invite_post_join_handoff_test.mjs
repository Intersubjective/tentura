import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLanding } from './landing_browser_fake.mjs';

const handoffKey = 'tentura_post_join_beacon';
const request = { id: 'B1', title: 'Fix the roof', kind: 'request' };
const inviterName = 'Vadim';

function renderRequestInvite({ audience, lapse }) {
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
    `request-handoff-${audience}-${lapse}`,
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
