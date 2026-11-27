// #663: the invite landing, the sign-up name step and the pager were English
// for a Russian browser, while the app that opens right after them is
// Russian. The landing now picks its language from the browser (or `?lang=`)
// and marks <html lang>. These tests check what the pages say, not source.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

globalThis.window = globalThis;

// The i18n table lives in onboarding.js: a new landing file would also need
// a CI deploy-list change.
const {
  TRANSLATIONS,
  getLocale,
  initLocale,
  pickLocale,
  setLocale,
  t,
  ONBOARDING_PAGES,
  authErrorMessage,
  inviteLandingCopy,
  inviterDisplayName,
  renderPostSignup,
  saveDisplayName,
} = await import('../onboarding.js');
const { parseInviteEntryInput } = await import('../invite_entry.js');
const { startEmailMagicLink } = await import('../auth.js');

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const CYRILLIC = /[а-яё]/i;

/** Runs [fn] with the landing in Russian, then puts English back. */
async function inRussian(fn) {
  setLocale('ru');
  try {
    return await fn();
  } finally {
    setLocale('en');
  }
}

/** Tiny DOM stand-in: elements, text, attributes, events, lookup by id/class. */
function installDom() {
  class Node {
    constructor(nodeType, tagName = '') {
      this.nodeType = nodeType;
      this.tagName = tagName;
      this.children = [];
      this.attrs = {};
      this.listeners = {};
      this.className = '';
      this.hidden = false;
      this.checked = false;
      this.disabled = false;
      this.data = '';
    }
    setAttribute(k, v) {
      this.attrs[k] = String(v);
      if (k === 'value') this.value = String(v);
      if (k === 'checked') this.checked = true;
      if (k === 'disabled') this.disabled = true;
    }
    getAttribute(k) {
      return this.attrs[k] ?? null;
    }
    addEventListener(type, fn) {
      (this.listeners[type] ??= []).push(fn);
    }
    append(...nodes) {
      for (const n of nodes) if (n != null) this.children.push(n);
    }
    replaceChildren(...nodes) {
      this.children = [];
      this.append(...nodes);
    }
    get textContent() {
      if (this.nodeType === 3) return this.data;
      return this.children.map((c) => c.textContent).join('');
    }
    set textContent(v) {
      const n = new Node(3);
      n.data = String(v);
      this.children = [n];
    }
    focus() {
      globalThis.document.activeElement = this;
    }
    all(pred) {
      const out = pred(this) ? [this] : [];
      for (const c of this.children) out.push(...c.all(pred));
      return out;
    }
    querySelector(sel) {
      return (
        this.all((n) =>
          sel.startsWith('#')
            ? n.attrs.id === sel.slice(1)
            : sel.startsWith('.')
              ? String(n.className).split(/\s+/).includes(sel.slice(1))
              : n.tagName === sel.toUpperCase(),
        )[0] ?? null
      );
    }
    fire(type) {
      for (const fn of this.listeners[type] || []) fn({ preventDefault() {} });
    }
  }
  globalThis.document = {
    createElement: (tag) => new Node(1, tag.toUpperCase()),
    createTextNode: (text) => {
      const n = new Node(3);
      n.data = String(text);
      return n;
    },
  };
}

function renderNameStep(displayName = 'New member') {
  installDom();
  const card = document.createElement('div');
  renderPostSignup({
    card,
    profile: { id: 'U1', displayName },
    setState: () => {},
    setPageTitle: () => {},
    track: () => {},
    openProductUrl: () => '/app/',
    storage: { getItem: () => null, setItem: () => {} },
  });
  return card;
}

const settle = () => new Promise((r) => setTimeout(r, 0));

test('a Russian browser gets Russian, other browsers English', () => {
  assert.equal(pickLocale({ languages: ['ru-RU', 'ru', 'en-US'] }), 'ru');
  assert.equal(pickLocale({ languages: ['de-DE', 'ru'] }), 'ru');
  assert.equal(pickLocale({ language: 'ru' }), 'ru');
  assert.equal(pickLocale({ languages: ['en-GB', 'ru'] }), 'en');
  assert.equal(pickLocale({ languages: ['fr-FR'] }), 'en');
  assert.equal(pickLocale({}), 'en');
});

test('?lang= overrides the browser language when it names a supported one', () => {
  assert.equal(pickLocale({ languages: ['en-US'], search: '?lang=ru' }), 'ru');
  assert.equal(
    pickLocale({ languages: ['ru-RU'], search: '?code=x&lang=en' }),
    'en',
  );
  assert.equal(pickLocale({ languages: ['ru-RU'], search: '?lang=xx' }), 'ru');
});

test('navigator.language ru-RU marks the page <html lang="ru">', () => {
  const documentElement = { lang: 'en' };
  let spinnerLabel = null;
  const locale = initLocale({
    navigator: { language: 'ru-RU', languages: ['ru-RU', 'ru'] },
    location: { search: '' },
    document: {
      documentElement,
      querySelector: (sel) =>
        sel === '.spinner'
          ? { setAttribute: (k, v) => (spinnerLabel = v) }
          : null,
    },
  });
  try {
    assert.equal(locale, 'ru');
    assert.equal(getLocale(), 'ru');
    assert.equal(documentElement.lang, 'ru');
    assert.match(spinnerLabel, CYRILLIC);
  } finally {
    setLocale('en');
  }
});

test('an English browser keeps <html lang="en"> and English copy', () => {
  const documentElement = { lang: 'en' };
  initLocale({
    navigator: { language: 'en-US', languages: ['en-US'] },
    location: { search: '' },
    document: { documentElement },
  });
  assert.equal(documentElement.lang, 'en');
  assert.equal(t('Welcome to Tentura'), 'Welcome to Tentura');
});

test('the name step speaks Russian to a Russian browser', async () => {
  await inRussian(async () => {
    const card = renderNameStep();
    const text = card.textContent;
    assert.match(text, /Добро пожаловать в Tentura/);
    assert.match(text, /Как к вам обращаться\?/);
    assert.doesNotMatch(text, /What should people call you|Save & continue/);
    const input = card.querySelector('#display-name');
    assert.match(input.getAttribute('placeholder'), CYRILLIC);

    // Empty name: the error is Russian too.
    input.value = '  ';
    card.querySelector('FORM').fire('submit');
    assert.equal(card.querySelector('.error').textContent, 'Введите имя.');
  });
});

// #660 strings: the server placeholder inviter and the way on after a failed
// name save.
test('a failed name save and a placeholder inviter read Russian too', async () => {
  await inRussian(async () => {
    assert.equal(inviterDisplayName('New member'), 'Друг');
    assert.equal(t('{name} shared', { name: inviterDisplayName('  ') }), 'Кто-то делится');

    const card = renderNameStep();
    globalThis.fetch = async () => ({ ok: false, status: 500 });
    card.querySelector('#display-name').value = 'Саня';
    chooseDiscoverability(card, 'Нет');
    card.querySelector('FORM').fire('submit');
    await settle();
    await settle();

    assert.equal(
      card.querySelector('.error').textContent,
      'Не удалось сохранить имя. Попробуйте ещё раз.',
    );
    const onward = card.querySelector('.name-continue');
    assert.equal(onward.hidden, false);
    assert.equal(onward.textContent, 'Продолжить без имени');
    assert.doesNotMatch(card.textContent, /Try again|Continue without a name/);

    globalThis.fetch = async () => {
      throw new TypeError('Failed to fetch');
    };
    await assert.rejects(saveDisplayName('Саня'), (err) =>
      err.message.startsWith('Не удалось связаться с сервером.'),
    );
  });
});

test('the pager speaks Russian and uses the app wording for its pages', async () => {
  await inRussian(async () => {
    const card = renderNameStep();
    globalThis.fetch = async () => ({
      ok: true,
      json: async () => ({ id: 'U1', displayName: 'Саня' }),
    });
    card.querySelector('#display-name').value = 'Саня';
    chooseDiscoverability(card, 'Нет');
    card.querySelector('FORM').fire('submit');
    await settle();
    await settle();

    const pager = card.querySelector('.pager');
    assert.ok(pager, 'pager shown after the name is saved');
    assert.equal(
      pager.querySelector('H1').textContent,
      'Решайте задачи через людей, которым доверяете',
    );
    assert.equal(pager.querySelector('.pager-progress').textContent, 'Шаг 1 из 3');
    assert.equal(
      pager.querySelector('.hint-link').textContent,
      'Пропустить — открыть Tentura',
    );
    assert.doesNotMatch(pager.textContent, /Next|Skip|Step \d/);
  });
});

test('the invite copy is Russian, and its about line opens the first pager page', async () => {
  await inRussian(() => {
    const plain = inviteLandingCopy({ inviterName: 'Мира', inApp: false });
    assert.match(plain.about, CYRILLIC);
    assert.match(plain.why, /^Мира /);
    assert.match(plain.why, CYRILLIC);
    assert.ok(t(ONBOARDING_PAGES[0].body).startsWith(plain.about));
    assert.match(plain.recoverLink, CYRILLIC);

    const request = inviteLandingCopy({
      inviterName: 'Мира',
      hasRequest: true,
      inApp: true,
    });
    assert.match(request.why, /запрос/);
    assert.match(request.signUp, /браузер/);

    const post = inviteLandingCopy({
      inviterName: 'Мира',
      hasRequest: true,
      isPost: true,
      inApp: false,
    });
    assert.match(post.why, /пост/);
    assert.doesNotMatch(post.why, /запрос/);
  });
});

test('sign-in and invite-entry errors are Russian too', async () => {
  await inRussian(async () => {
    assert.match(authErrorMessage('?auth_error=google_failed'), /Google/);
    assert.match(authErrorMessage('?auth_error=google_failed'), CYRILLIC);
    assert.match(parseInviteEntryInput('').error, CYRILLIC);
    assert.match(parseInviteEntryInput('nope').error, CYRILLIC);
    await assert.rejects(
      startEmailMagicLink({ email: 'not-an-email' }),
      (err) => CYRILLIC.test(err.message),
    );
  });
});

// Guard: every English literal the landing passes to t() has a Russian
// entry, so a new string cannot silently stay English for Russian readers.
test('every string the landing translates has a Russian entry', () => {
  const files = ['main.js', 'onboarding.js', 'auth.js', 'invite_entry.js'];
  const used = new Set();
  for (const file of files) {
    const src = readFileSync(join(root, file), 'utf8');
    for (const m of src.matchAll(/\bt\(\s*(['"])((?:\\.|(?!\1).)*)\1/gs)) {
      used.add(m[2].replace(/\\(.)/g, '$1'));
    }
  }
  assert.ok(used.size > 50, `found ${used.size} translated strings`);
  for (const text of used) {
    assert.ok(text in TRANSLATIONS.ru, `missing Russian for: ${text}`);
    assert.match(TRANSLATIONS.ru[text], CYRILLIC, `not Russian: ${text}`);
  }
  // The onboarding pages are translated by their English text.
  for (const page of ONBOARDING_PAGES) {
    assert.ok(page.title in TRANSLATIONS.ru, page.title);
    assert.ok(page.body in TRANSLATIONS.ru, page.body);
  }
});

// Guard: no visible text in main.js / onboarding.js bypasses t().
test('landing pages put no raw English text on screen', () => {
  for (const file of ['main.js', 'onboarding.js']) {
    const src = readFileSync(join(root, file), 'utf8');
    const rawChild = src.match(/\bel\(\s*'\w+',\s*\{[^{}]*\},\s*['"`]/g) || [];
    assert.deepEqual(rawChild, [], `${file}: el() with a raw text child`);
    const rawText = src.match(/textContent = ['"`][^'"`]/g) || [];
    assert.deepEqual(rawText, [], `${file}: textContent set to a raw literal`);
  }
});

test('main.js picks the locale before it renders anything', () => {
  const mainJs = readFileSync(join(root, 'main.js'), 'utf8');
  assert.match(mainJs, /\binitLocale\b[^;]*from '\.\/onboarding\.js'/s);
  const init = mainJs.indexOf('initLocale()');
  assert.ok(init > 0, 'initLocale() is called');
  assert.ok(init < mainJs.indexOf('\nmain();'), 'before main() runs');
});

const discoverabilityLabel = "People who have my email can see I'm on Tentura";
const profilePath = '/api/v2/accounts/me/profile';

function choiceRadios(card) {
  return card.all((node) => node.tagName === 'INPUT' && node.attrs.type === 'radio');
}

function radioLabel(card, radio) {
  return card.all((node) =>
    node.tagName === 'LABEL' &&
    ((radio.attrs.id && node.attrs.for === radio.attrs.id) ||
      node.all((child) => child === radio).length > 0)
  )[0]?.textContent.trim();
}

function chooseDiscoverability(card, label) {
  const radio = choiceRadios(card).find((node) => radioLabel(card, node) === label);
  assert.ok(radio, `The name step offers ${label}`);
  // A browser checks the input before dispatching input/change events.
  radio.checked = true;
  radio.fire('input');
  radio.fire('change');
}

function nameStepAlert(card) {
  const alerts = card.all((node) => node.attrs.role === 'alert');
  assert.equal(alerts.length, 1);
  return alerts[0];
}

function interceptProfileSave(testContext, respond) {
  const requests = [];
  testContext.mock.method(globalThis, 'fetch', async (url, init) => {
    const path = new URL(url, 'https://tentura.test').pathname;
    const body = JSON.parse(init.body);
    requests.push({ path, method: init.method, credentials: init.credentials, body });
    return respond(body);
  });
  return requests;
}

function successfulNameSave(body) {
  return { ok: true, json: async () => ({ id: 'U1', ...body }) };
}

test('Name step email discoverability offers an unanswered Yes or No in both locales', async () => {
  setLocale('en');
  const english = renderNameStep();
  assert.ok(english.textContent.includes(discoverabilityLabel));
  assert.deepEqual(choiceRadios(english).map((radio) => radioLabel(english, radio)).sort(), ['No', 'Yes']);
  assert.doesNotMatch(english.textContent, /phantom/i);

  await inRussian(async () => {
    const russian = renderNameStep();
    const translatedLabel = TRANSLATIONS.ru[discoverabilityLabel];
    assert.match(translatedLabel, CYRILLIC);
    assert.ok(russian.textContent.includes(translatedLabel));
    assert.equal(TRANSLATIONS.ru.Yes, 'Да');
    assert.equal(TRANSLATIONS.ru.No, 'Нет');
    assert.deepEqual(choiceRadios(russian).map((radio) => radioLabel(russian, radio)).sort(), ['Да', 'Нет']);
    assert.doesNotMatch(russian.textContent, /phantom/i);

    for (const card of [english, russian]) {
      for (const radio of choiceRadios(card)) {
        assert.ok(!radio.checked && radio.getAttribute('checked') === null);
        assert.equal(radio.disabled, false);
      }
    }
  });
});

test('Name step email discoverability blocks submission until a choice is made and explains why in both locales', async (context) => {
  const requests = interceptProfileSave(context, successfulNameSave);

  const submitWithoutChoice = async () => {
    const card = renderNameStep();
    card.querySelector('#display-name').value = 'Ada Lovelace';
    const form = card.querySelector('form');
    form.fire('submit');
    await settle();
    assert.deepEqual(requests, [], 'A valid name alone must send no request');
    assert.equal(card.querySelector('form'), form, 'The name form stays open');
    assert.equal(card.querySelector('.pager'), null);
    return nameStepAlert(card).textContent;
  };

  setLocale('en');
  const englishError = await submitWithoutChoice();
  assert.match(englishError, /choose|select|answer|pick/i);
  assert.doesNotMatch(englishError, /phantom/i);
  await inRussian(async () => {
    const russianError = await submitWithoutChoice();
    assert.match(russianError, /выбер|выбор|укаж|ответ/i);
    assert.equal(russianError, TRANSLATIONS.ru[englishError]);
    assert.doesNotMatch(russianError, /phantom/i);
  });
});

for (const [label, discoverability] of [['Yes', true], ['No', false]]) {
  test(`Name step email discoverability saves ${label} with the new name before showing the pager`, async (context) => {
    let releaseSave;
    const pending = new Promise((resolve) => { releaseSave = resolve; });
    const requests = interceptProfileSave(context, async (body) => {
      await pending;
      return successfulNameSave(body);
    });
    setLocale('en');
    const card = renderNameStep();
    card.querySelector('#display-name').value = 'Ada Lovelace';
    chooseDiscoverability(card, label);

    try {
      card.querySelector('form').fire('submit');
      await settle();
      assert.deepEqual(requests, [{
        path: profilePath,
        method: 'PATCH',
        credentials: 'include',
        body: { displayName: 'Ada Lovelace', discoverability },
      }]);
      assert.ok(card.querySelector('#display-name'), 'The name step stays open while saving');
      assert.equal(card.querySelector('.pager'), null);
    } finally {
      releaseSave();
      await settle();
    }
    assert.ok(card.querySelector('.pager'));
  });
}

test('Name step email discoverability saves the choice when the prefilled name is unchanged', async (context) => {
  const requests = interceptProfileSave(context, successfulNameSave);
  setLocale('en');
  const card = renderNameStep('Ada Lovelace');
  assert.equal(card.querySelector('#display-name').value, 'Ada Lovelace');
  chooseDiscoverability(card, 'No');
  card.querySelector('form').fire('submit');
  await settle();

  assert.equal(requests.length, 1, 'The choice must be saved even without a name change');
  assert.equal(requests[0].path, profilePath);
  assert.equal(requests[0].method, 'PATCH');
  assert.equal(requests[0].credentials, 'include');
  assert.equal(requests[0].body.discoverability, false);
  assert.ok(card.querySelector('.pager'));
});

for (const [failure, respond] of [
  ['server rejection', async () => ({ ok: false, status: 500 })],
  ['network failure', async () => { throw new TypeError('raw network failure'); }],
]) {
  test(`Name step email discoverability keeps the form retryable after a ${failure}`, async (context) => {
    const requests = interceptProfileSave(context, respond);
    const attemptSave = async (option, retryLabel) => {
      const previousRequests = requests.length;
      const card = renderNameStep('Ada Lovelace');
      chooseDiscoverability(card, option);
      const form = card.querySelector('form');
      form.fire('submit');
      await settle();

      assert.equal(requests.length, previousRequests + 1);
      assert.equal(requests.at(-1).body.discoverability, false);
      assert.equal(card.querySelector('form'), form);
      assert.equal(card.querySelector('.pager'), null);
      const submit = form.all((node) => node.tagName === 'BUTTON' && node.attrs.type === 'submit')[0];
      assert.equal(submit.disabled, false);
      assert.equal(submit.textContent, retryLabel);
      const error = nameStepAlert(card).textContent;
      assert.match(error, /\S/);
      assert.doesNotMatch(error, /phantom|raw network failure/i);
      return error;
    };

    setLocale('en');
    const englishError = await attemptSave('No', 'Try again');
    await inRussian(async () => {
      const russianError = await attemptSave('Нет', 'Попробовать ещё раз');
      assert.match(russianError, CYRILLIC);
      assert.equal(russianError, TRANSLATIONS.ru[englishError]);
    });
  });
}
