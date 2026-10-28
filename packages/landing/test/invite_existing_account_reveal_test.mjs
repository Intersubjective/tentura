// The signed-out invite page and the no-invite page share one existing-account
// toggle. These tests render the real main.js against a minimal DOM fake (the
// landing has no npm, so no jsdom) and look at what a person would see.
import test from 'node:test';
import assert from 'node:assert/strict';

class FakeNode {
  constructor(nodeType, tagName = '') {
    this.nodeType = nodeType;
    this.tagName = tagName;
    this.children = [];
    this.attrs = {};
    this.listeners = {};
    this.className = '';
    this.hidden = false;
    this.disabled = false;
    this.value = '';
  }
  setAttribute(k, v) {
    this.attrs[k] = String(v);
    if (k === 'hidden') this.hidden = true;
  }
  getAttribute(k) {
    return this.attrs[k] ?? null;
  }
  removeAttribute(k) {
    delete this.attrs[k];
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
    this.children = [];
    if (v) {
      const text = new FakeNode(3);
      text.data = String(v);
      this.children.push(text);
    }
  }
  get classList() {
    return { toggle() {}, add() {}, remove() {} };
  }
  focus() {}
  querySelector(sel) {
    return this.querySelectorAll(sel)[0] ?? null;
  }
  querySelectorAll(sel) {
    const out = [];
    this.walk((n) => {
      if (n.nodeType !== 1) return;
      const classes = String(n.className).split(/\s+/);
      const matches = sel.startsWith('#')
        ? n.attrs.id === sel.slice(1)
        : sel.startsWith('.')
          ? classes.includes(sel.slice(1))
          : n.tagName === sel.toUpperCase();
      if (matches) {
        out.push(n);
      }
    });
    return out;
  }
  walk(fn) {
    fn(this);
    for (const c of this.children) c.walk?.(fn);
  }
  click() {
    for (const fn of this.listeners.click ?? []) fn({ preventDefault() {} });
  }
  /** True when this node or an ancestor-hidden chain would hide it. */
  isShownIn(root) {
    let shown = true;
    const visit = (node, hiddenAbove) => {
      const hiddenHere = hiddenAbove || node.hidden === true;
      if (node === this) shown = !hiddenHere;
      for (const c of node.children) if (c.nodeType === 1) visit(c, hiddenHere);
    };
    visit(root, false);
    return shown;
  }
}

function installBrowserFake({ pathname, preview }) {
  const card = new FakeNode(1, 'DIV');
  const app = new FakeNode(1, 'DIV');
  globalThis.window = globalThis;
  globalThis.addEventListener ??= () => {};
  globalThis.TENTURA = { googleEnabled: true };
  globalThis.document = {
    title: '',
    documentElement: {},
    getElementById: (id) => (id === 'card' ? card : app),
    createElement: (tag) => new FakeNode(1, tag.toUpperCase()),
    createTextNode: (text) => {
      const n = new FakeNode(3);
      n.data = String(text);
      return n;
    },
    createDocumentFragment: () => new FakeNode(11, '#fragment'),
    querySelector: () => null,
    addEventListener() {},
  };
  globalThis.location = {
    pathname,
    search: '',
    hash: '',
    origin: 'https://tentura.test',
    href: `https://tentura.test${pathname}`,
    replace() {},
  };
  Object.defineProperty(globalThis, 'navigator', {
    value: { userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130', language: 'en-US', languages: ['en-US'] },
    configurable: true,
  });
  const store = new Map();
  globalThis.sessionStorage = {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => store.set(k, String(v)),
    removeItem: (k) => store.delete(k),
  };
  globalThis.TENTURA = { googleEnabled: true };
  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    json: async () => preview ?? {},
  });
  return card;
}

async function renderLanding(options, tag) {
  const card = installBrowserFake(options);
  await import(`../main.js?${tag}`);
  for (let i = 0; i < 50 && card.children.length === 0; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.ok(card.children.length > 0, 'the landing rendered nothing');
  return card;
}

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
