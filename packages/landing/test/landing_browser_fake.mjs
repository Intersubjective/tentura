// Minimal DOM/location fake for loading packages/landing/main.js under node:test.
import assert from 'node:assert/strict';

export class FakeNode {
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
      if (matches) out.push(n);
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

/**
 * @param {{
 *   pathname: string,
 *   search?: string,
 *   hash?: string,
 *   preview?: object,
 *   previewFails?: boolean,
 *   languages?: string[],
 * }} options
 */
export function installBrowserFake(options) {
  const {
    pathname,
    search = '',
    hash = '',
    preview,
    previewFails = false,
    languages = ['en-US'],
  } = options;
  const card = new FakeNode(1, 'DIV');
  const app = new FakeNode(1, 'DIV');
  const state = { replaceTo: null };
  globalThis.window = globalThis;
  globalThis.addEventListener ??= () => {};
  globalThis.TENTURA = { googleEnabled: true };
  globalThis.document = {
    title: '',
    documentElement: { lang: 'en' },
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
    search,
    hash,
    origin: 'https://tentura.test',
    href: `https://tentura.test${pathname}${search}${hash}`,
    replace(url) {
      state.replaceTo = String(url);
    },
    assign() {},
  };
  globalThis.history = { replaceState() {} };
  Object.defineProperty(globalThis, 'navigator', {
    value: {
      userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/130',
      language: languages[0],
      languages,
    },
    configurable: true,
  });
  const store = new Map();
  globalThis.sessionStorage = {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => store.set(k, String(v)),
    removeItem: (k) => store.delete(k),
  };
  if (previewFails) {
    globalThis.fetch = async () => ({
      ok: false,
      status: 500,
      json: async () => ({}),
    });
  } else {
    globalThis.fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => preview ?? {},
    });
  }
  card._landingTestState = state;
  return card;
}

export async function renderLanding(options, tag, { expectContent = true } = {}) {
  const card = installBrowserFake(options);
  await import(`../main.js?${tag}`);
  for (let i = 0; i < 50; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
    if (card._landingTestState.replaceTo) break;
    if (card.children.length > 0) break;
  }
  if (expectContent) {
    assert.ok(
      card.children.length > 0 || card._landingTestState.replaceTo,
      'the landing rendered nothing and did not redirect',
    );
  }
  return card;
}

export function landingReplaceTo(card) {
  return card._landingTestState?.replaceTo ?? null;
}
