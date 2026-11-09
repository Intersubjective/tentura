// The signed-out invite page and the no-invite page share one existing-account
// toggle. These tests render the real main.js against a minimal DOM fake (the
// landing has no npm, so no jsdom) and look at what a person would see.
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLanding } from './landing_browser_fake.mjs';

const SIGNED_OUT_INVITE = {
  pathname: '/invite/Iabc123',
  preview: {
    codeStatus: 'available',
    callerStatus: 'anonymous',
    suggestedAction: 'accept-as-new',
    inviter: { id: 'U1', displayName: 'Nina' },
  },
};

const NO_INVITE = { pathname: '/' };

const EXISTING_ACCOUNT = 'I already have an account';

const buttonsLabelled = (root, label) =>
  root.querySelectorAll('button').filter((b) => b.textContent === label);

const seedRecoveryLinks = (root) =>
  root.querySelectorAll('a').filter((a) => /\/recover\b/.test(a.getAttribute('href') ?? ''));

test('a signed-out invite offers an «I already have an account» toggle', async () => {
  const card = await renderLanding(SIGNED_OUT_INVITE, 'invite-toggle');
  const toggles = buttonsLabelled(card, EXISTING_ACCOUNT);
  assert.equal(toggles.length, 1);
  assert.ok(toggles[0].isShownIn(card), 'the toggle is hidden');
  assert.equal(toggles[0].getAttribute('aria-expanded'), 'false');
});

test('a signed-out invite shows no seed-recovery link until the toggle is opened', async () => {
  const card = await renderLanding(SIGNED_OUT_INVITE, 'invite-hidden');
  // Not merely hidden: the link is not in the page at all until it is asked for.
  assert.deepEqual(seedRecoveryLinks(card), []);
});

test('opening the toggle on a signed-out invite reveals the seed-recovery link', async () => {
  const card = await renderLanding(SIGNED_OUT_INVITE, 'invite-reveal');
  buttonsLabelled(card, EXISTING_ACCOUNT)[0].click();
  const links = seedRecoveryLinks(card).filter((a) => a.isShownIn(card));
  assert.equal(links.length, 1);
  assert.equal(links[0].textContent, EXISTING_ACCOUNT);
});

test('a signed-out invite still offers email and Google sign-in up front', async () => {
  const card = await renderLanding(SIGNED_OUT_INVITE, 'invite-primary');
  const google = card
    .querySelectorAll('a')
    .filter((a) => a.textContent === 'Continue with Google' && a.isShownIn(card));
  assert.equal(google.length, 1);
  assert.ok(card.querySelector('#email-signin')?.isShownIn(card));
});

test('the no-invite page keeps sign-in open with the seed link, and no toggle', async () => {
  const card = await renderLanding(NO_INVITE, 'no-invite');
  assert.ok(card.querySelector('#email-signin')?.isShownIn(card));
  const links = seedRecoveryLinks(card).filter((a) => a.isShownIn(card));
  assert.equal(links.length, 1);
  assert.equal(links[0].textContent, EXISTING_ACCOUNT);
  assert.deepEqual(
    buttonsLabelled(card, EXISTING_ACCOUNT).filter((b) => b.isShownIn(card)),
    [],
  );
});
