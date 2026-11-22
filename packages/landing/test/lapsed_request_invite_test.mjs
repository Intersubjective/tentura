import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLanding } from './landing_browser_fake.mjs';

function renderRequestInvite(language, { lapsed, existingUser = false }) {
  return renderLanding(
    {
      pathname: '/invite/Iabc123',
      languages: [language],
      preview: {
        inviter: { displayName: 'Vadim' },
        codeStatus: 'available',
        callerStatus: existingUser ? 'existing-user' : 'anonymous',
        suggestedAction: existingUser ? 'accept-as-existing' : 'accept-as-new',
        beacon: {
          id: 'B1',
          kind: 'request',
          title: 'Fix the roof',
          snippet: '',
          description: '',
          lapsed,
        },
      },
    },
    `${language}-${lapsed}-${existingUser}`,
  );
}

function assertJoinOptions(card, { email, google, existingAccount }) {
  assert.ok(card.querySelector('#email-signin')?.isShownIn(card), 'visible email field');
  const buttons = card.querySelectorAll('button').filter((button) => button.isShownIn(card));
  assert.ok(buttons.some((button) => button.textContent === email), 'email sign-up button');
  assert.ok(
    card.querySelectorAll('a').some((link) => link.textContent === google && link.isShownIn(card)),
    'Google sign-in option',
  );
  assert.ok(
    buttons.some((button) =>
      button.textContent === existingAccount && button.getAttribute('aria-expanded') === 'false'),
    'existing-account toggle',
  );
}

const closedInEnglish = /Vadim invited you to «Fix the roof», but it has already closed\./;
const welcomeInEnglish = /You['’]re still welcome on Tentura/i;
const connectedInEnglish = /you['’]re now connected with Vadim/i;
const internalTerminology = /phantom|фантом/iu;
const activeRequestInEnglish = /Vadim wants your help with the request above/;
const activeRequestInRussian = /Vadim просит вашей помощи с запросом выше/;
// The Russian app copy says «но он уже закрыт». Keep the landing phrasing
// flexible while requiring the closure and both substitutions in one sentence.
const noticeInRussian = /(?=[^.!?]*Vadim)(?=[^.!?]*«Fix the roof»)[^.!?]*уже (?:закрыт[аоы]?|закрылся|заверш[её]н[аоы]?)(?![а-яё])/iu;

test('a closed Request invite still welcomes new members in English', async () => {
  const active = await renderRequestInvite('en-US', { lapsed: false });
  assert.equal(active.querySelector('h1')?.textContent, 'Vadim invited you to Tentura');
  assert.match(active.textContent, activeRequestInEnglish);
  assert.doesNotMatch(active.textContent, /already closed/i);

  const closed = await renderRequestInvite('en-US', { lapsed: true });
  assertJoinOptions(closed, {
    email: 'Email me a sign-in link',
    google: 'Continue with Google',
    existingAccount: 'I already have an account',
  });
  assert.doesNotMatch(closed.textContent, internalTerminology);
  assert.match(closed.textContent, closedInEnglish);
  assert.match(closed.textContent, /You['’]re still welcome on Tentura, and you['’]re now connected with Vadim\./);
  assert.doesNotMatch(closed.textContent, activeRequestInEnglish);
});

test('a closed Request invite explains the closure and keeps sign-up available in Russian', async () => {
  const active = await renderRequestInvite('ru-RU', { lapsed: false });
  assert.equal(active.querySelector('h1')?.textContent, 'Vadim приглашает вас в Tentura');
  assert.match(active.textContent, activeRequestInRussian);
  assert.doesNotMatch(active.textContent, noticeInRussian);

  const closed = await renderRequestInvite('ru-RU', { lapsed: true });
  assertJoinOptions(closed, {
    email: 'Прислать ссылку для входа',
    google: 'Продолжить через Google',
    existingAccount: 'У меня уже есть аккаунт',
  });
  assert.doesNotMatch(closed.textContent, internalTerminology);
  assert.doesNotMatch(closed.textContent, /but it has already closed/i);
  assert.doesNotMatch(closed.textContent, welcomeInEnglish);
  assert.match(closed.textContent, noticeInRussian);
  assert.doesNotMatch(closed.textContent, activeRequestInRussian);
});

test('a closed Request invite tells existing members about the closure in English', async () => {
  const card = await renderRequestInvite('en-US', { lapsed: true, existingUser: true });
  assert.doesNotMatch(card.textContent, internalTerminology);
  assert.match(card.textContent, closedInEnglish);
  assert.doesNotMatch(card.textContent, welcomeInEnglish);
  assert.doesNotMatch(card.textContent, connectedInEnglish);
  assert.doesNotMatch(card.textContent, /Accept the invite in the app to become friends\./);
});

test('a closed Request invite shows existing members only the closure notice in Russian', async () => {
  const card = await renderRequestInvite('ru-RU', { lapsed: true, existingUser: true });
  assert.doesNotMatch(card.textContent, internalTerminology);
  // Allow the Request preview, closure heading, and accept link around the notice.
  const message = card.textContent.trim()
    .replace(/^Vadim делится\s*Fix the roof\s*/, '')
    .replace(/^Запрос закрыт\s*/, '')
    .replace(/\s*Открыть Tentura и принять$/, '');
  assert.equal(message, 'Vadim пригласил вас в запрос «Fix the roof», но он уже закрыт.');
});
