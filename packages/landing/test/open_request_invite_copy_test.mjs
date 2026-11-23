import test from 'node:test';
import assert from 'node:assert/strict';
import { renderLanding } from './landing_browser_fake.mjs';

const code = 'Iabc123';

function renderExistingInvite(language, beacon) {
  return renderLanding(
    {
      pathname: `/invite/${code}`,
      languages: [language],
      preview: {
        inviter: { displayName: 'Vadim' },
        codeStatus: 'available',
        callerStatus: 'existing-user',
        suggestedAction: 'accept-as-existing',
        ...(beacon && { beacon }),
      },
    },
    `${language}-${beacon ? 'request' : 'plain'}`,
  );
}

const request = {
  id: 'B1',
  kind: 'request',
  title: 'Fix the roof',
  lapsed: false,
};

for (const [language, heading, friendship, acceptLabel, admission] of [
  [
    'en-US',
    'Vadim wants to connect',
    'Accept the invite in the app to become friends.',
    'Open Tentura to accept',
    /(?=[^.!?]*\baccept\w*)(?=[^.!?]*\bin (?:the )?app\b)(?=[^.!?]*\bonly\b)[^.!?]*access to (?:this|the) request\b/i,
  ],
  [
    'ru-RU',
    'Vadim хочет добавить вас в свою сеть',
    'Примите приглашение в приложении, чтобы стать друзьями.',
    'Открыть Tentura и принять',
    /(?=[^.!?]*(?:приняти|примите|принять))(?=[^.!?]*в приложении)(?=[^.!?]*только)[^.!?]*доступ(?:\s+только)? к (?:этому )?запросу/iu,
  ],
]) {
  test(`existing users see Request access only and can open the app (${language})`, async () => {
    const plain = await renderExistingInvite(language);
    assert.equal(plain.querySelector('h1')?.textContent, heading);
    assert.ok(plain.textContent.includes(friendship), 'plain invite explains friendship');

    const card = await renderExistingInvite(language, request);
    const title = card.querySelector('h1');
    assert.ok(title?.textContent && title.isShownIn(card), 'visible invite heading');
    assert.ok(card.textContent.includes(request.title), 'the Request is named');
    const accept = card.querySelectorAll('a').find((link) => link.textContent === acceptLabel);
    assert.ok(accept?.isShownIn(card), 'visible open-app accept link');
    assert.equal(new URL(accept.getAttribute('href')).hash, `#/accept-invite/${code}`);

    const visibleCopy = [title, ...card.querySelectorAll('p')]
      .filter((node) => node.isShownIn(card))
      .map((node) => node.textContent);
    assert.ok(
      visibleCopy.some((line) => admission.test(line)),
      `Expected a visible explanation of Request access only. Saw ${JSON.stringify(visibleCopy)}`,
    );
    assert.doesNotMatch(
      card.textContent,
      /wants to connect|become friends|хочет добавить вас в свою сеть|стать друзьями/iu,
    );
    if (language === 'ru-RU') assert.match(title.textContent, /[а-яё]/iu);
  });
}
