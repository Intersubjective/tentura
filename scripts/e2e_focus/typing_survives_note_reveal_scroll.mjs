// Real touch + keyboard input through the semantics-on profile/Wasm app.
// No DOM value assignment, synthetic blur, or focus repair is permitted here.
import assert from 'node:assert/strict';
import { chromium } from 'playwright';

const base = process.env.BASE || 'https://dev.lvh.me:9443';
const cycles = Number(process.argv[2] || 10);
const scenario = process.argv[3] || 'touch-lowest';
assert.ok(['touch-lowest', 'touch-first', 'mouse-first', 'reopen-preview'].includes(scenario),
  'scenario: touch-lowest | touch-first | mouse-first | reopen-preview');
const desktop = scenario === 'mouse-first';
const needsReveal = scenario === 'touch-lowest';
const escaped = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
assert.ok(Number.isInteger(cycles) && cycles >= 10, 'Use at least ten touch cycles');
let browser;
let page;
let deleteRequest;
try {
  browser = await chromium.launch({
    channel: 'chrome', headless: process.env.HEADLESS !== '0', args: ['--no-sandbox'],
  });
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: desktop ? { width: 1280, height: 800 } : { width: 375, height: 667 },
    isMobile: !desktop, hasTouch: !desktop,
    locale: 'ru-RU', serviceWorkers: 'block',
  });
  const login = await context.request.post(`${base}/api/v2/auth/email/test-login`, {
    data: { email: process.env.EMAIL || 'society-bravo3@test.tentura.local' },
  });
  assert.ok(login.ok(), `QA login prerequisite: HTTP ${login.status()}`);
  const tokenResponse = await context.request.post(`${base}/api/v2/session/access-token`);
  assert.ok(tokenResponse.ok(), 'Request fixture authentication');
  const { access_token: token } = await tokenResponse.json();
  assert.ok(token, 'Request fixture access token');
  const gql = async (query, variables) => {
    const response = await context.request.post(`${base}/api/v2/graphql`, {
      headers: { Authorization: `Bearer ${token}` }, data: { query, variables },
    });
    assert.ok(response.ok(), 'Request fixture HTTP response');
    const body = await response.json();
    assert.ok(!body.errors?.length, `Request fixture GraphQL: ${JSON.stringify(body.errors)}`);
    return body.data;
  };
  const created = await gql(
    'mutation { beaconCreate(title: "Personal note reveal scroll", description: "Browser focus regression fixture", draft: false, isDiscoverable: false) { id } }',
  );
  const id = created.beaconCreate.id;
  assert.ok(id, 'Real Request fixture created through the public API');
  deleteRequest = () => gql('mutation($id: String!) { beaconDeleteById(id: $id) }', { id });
  page = await context.newPage();
  page.setDefaultTimeout(15000);
  let wasmLoaded = false;
  page.on('response', (response) => {
    if (new URL(response.url()).pathname.endsWith('/main.dart.wasm') && response.ok()) wasmLoaded = true;
  });
  await page.addInitScript(() => {
    window.noteFocusTrace = [];
    window.noteFocusedElements = new WeakSet();
    for (const type of ['focusin', 'focusout', 'blur', 'scroll', 'keydown', 'input']) {
      document.addEventListener(type, (event) => {
        if (type === 'focusin') {
          for (let element = event.target; element; element = element.parentElement) {
            window.noteFocusedElements.add(element);
          }
        }
        window.noteFocusTrace.push({
          type, time: performance.now(), key: event.key,
          tag: event.target.tagName, active: document.activeElement?.tagName,
          related: event.relatedTarget?.tagName,
          identifier: event.target.getAttribute?.('flt-semantics-identifier'),
          scrollTop: event.target.scrollTop,
        });
      }, true);
    }
  });
  const tap = async (locator) => {
    const box = await locator.boundingBox();
    assert.ok(box && box.width > 0 && box.height > 0, 'Visible touch target prerequisite');
    const x = Math.round(box.x + box.width / 2);
    const y = Math.round(box.y + box.height / 2);
    if (desktop) await page.mouse.click(x, y);
    else await page.touchscreen.tap(x, y);
  };
  // Association is user-visible: the saved preview must share the selected
  // recipient's row, rather than merely appear somewhere on the page.
  const previewOnRecipientRow = async (checkbox, text) => {
    const preview = page.getByRole('button', {
      name: new RegExp(`^${escaped(text)}(?:\\s+${escaped(text)})*$`),
    });
    const checkboxBox = await checkbox.boundingBox();
    if (!checkboxBox) return null;
    // A semantics label and its text child can both expose the preview.
    // Select by the visible recipient row, not an assumed DOM match count.
    for (const candidate of await preview.all()) {
      if (!await candidate.isVisible()) continue;
      const previewBox = await candidate.boundingBox();
      if (previewBox && previewBox.y < checkboxBox.y + checkboxBox.height &&
          checkboxBox.y < previewBox.y + previewBox.height) return candidate;
    }
    return null;
  };
  const results = [];
  for (let cycle = 1; cycle <= cycles; cycle++) {
    // A fresh page state gives every cycle an empty note and an unscrolled
    // list; transport, mapping, cubit and widgets all run normally.
    await page.goto(`${base}/#/forward/${id}`);
    if (cycle > 1) await page.reload();
    await page.locator('flt-semantics').first().waitFor({ state: 'attached', timeout: 60000 });
    assert.equal(wasmLoaded, true, 'Serve a fresh --profile --wasm build via run.sh');
    assert.equal(await page.evaluate(() => crossOriginIsolated), true, 'Deployment isolation headers required');
    const checkboxes = page.locator('[flt-semantics-identifier^="forward.recipient.checkbox."]');
    await checkboxes.first().waitFor({ state: 'visible' });
    // Allow the real candidate response to finish laying out, before selecting
    // the last fully visible checkbox above the pinned submit footer.
    await page.waitForTimeout(400);
    const footer = await page.locator('[flt-semantics-identifier="forward.submit"]').boundingBox();
    assert.ok(footer, 'Pinned forward footer prerequisite');
    const visible = [];
    for (const checkbox of await checkboxes.all()) {
      const box = await checkbox.boundingBox();
      if (box && box.y >= 0 && box.y + box.height <= footer.y) visible.push({ checkbox, box });
    }
    visible.sort((a, b) => a.box.y - b.box.y);
    const chosen = needsReveal ? visible.at(-1) : visible[0];
    assert.ok(chosen, 'A fully visible selectable recipient is required');
    const identifier = await chosen.checkbox.getAttribute('flt-semantics-identifier');
    const userId = identifier.slice('forward.recipient.checkbox.'.length);
    const recipientName = await chosen.checkbox.getAttribute('aria-label');
    assert.ok(recipientName, 'The chosen recipient has an accessible name');
    await tap(chosen.checkbox);
    await page.waitForFunction((identifier) => document.querySelector(
      `[flt-semantics-identifier="${identifier}"]`,
    )?.getAttribute('aria-checked') === 'true', identifier);
    const addNote = page.getByRole('button', {
      name: new RegExp(`^(?:Add a note for |Добавить заметку для )${escaped(recipientName)}$`),
    });
    await addNote.waitFor({ state: 'visible' });
    const noteButtonBox = await addNote.boundingBox();
    assert.ok(noteButtonBox, 'The selected recipient exposes its note action');
    const spaceBelowRow = footer.y - (noteButtonBox.y + noteButtonBox.height);
    if (needsReveal) assert.ok(spaceBelowRow < 48,
      'The lowest row leaves less than one field height above the footer');
    else assert.ok(spaceBelowRow > 100,
      'The first row leaves enough space for its note without a reveal scroll');
    const note = page.getByRole('textbox', {
      name: new RegExp(`(?:Add a note for |Добавьте заметку для )${escaped(recipientName)} \\((?:optional|необязательно)\\)`),
    });
    const outside = page.getByText(/^(Автор:|Author:)$/).first();
    if (scenario === 'reopen-preview') {
      // Build the preview through real typing. The one field tap belongs to
      // preparing a saved note; after reopening there is no repairing tap.
      await tap(addNote);
      await note.waitFor({ state: 'visible' });
      await tap(note);
      await page.waitForTimeout(100);
      await page.keyboard.type(`saved${cycle}`, { delay: 40 });
      assert.equal(await note.inputValue(), `saved${cycle}`, 'Saved preview fixture uses real keyboard input');
      await tap(outside);
      await page.waitForTimeout(300);
      const savedPreview = await previewOnRecipientRow(chosen.checkbox, `saved${cycle}`);
      assert.ok(savedPreview && await note.count() === 0,
        'Saved preview belongs to the chosen recipient and the editor is collapsed');
    }
    // Sample Flutter's published recipient geometry relative to the pinned
    // footer. A document scroll moves both by the same amount and therefore
    // cannot impersonate the list's caret-reveal scroll. DOM scroll/focus
    // events remain diagnostic; no input focus tag is required.
    await page.evaluate((identifier) => {
      window.noteFocusTrace = [];
      window.noteFocusedElements = new WeakSet();
      const recipient = () => document.querySelector(
        `[flt-semantics-identifier="${identifier}"]`,
      );
      const footer = () => document.querySelector(
        '[flt-semantics-identifier="forward.submit"]',
      );
      const row = recipient();
      const pinned = footer();
      const initial = row.getBoundingClientRect().top - pinned.getBoundingClientRect().top;
      const measure = window.noteRevealGeometry = {
        initial, minimum: initial, samples: 0, stopped: false,
      };
      const sample = () => {
        if (measure.stopped) return;
        const row = recipient();
        const pinned = footer();
        if (row && pinned) {
          const relative = row.getBoundingClientRect().top - pinned.getBoundingClientRect().top;
          measure.minimum = Math.min(measure.minimum, relative);
          measure.samples++;
        }
        requestAnimationFrame(sample);
      };
      requestAnimationFrame(sample);
    }, identifier);
    if (scenario === 'reopen-preview') await tap(await previewOnRecipientRow(chosen.checkbox, `saved${cycle}`));
    else await tap(addNote);
    // Synchronize only with the editor being built, never with focus recovery.
    // This avoids sending the first key before Flutter processes the tap.
    const editorAppeared = await note.waitFor({ state: 'attached', timeout: 1000 })
      .then(() => true, () => false);
    // Attachment precedes the engine's first editing connection by a frame.
    // Begin on its FIRST focus, not after a delay or after recovery: the
    // regression starts with a focused editor and then loses it during reveal.
    // Keep using the exact recipient's textbox; no tag-based focus assumption,
    // second tap, DOM focus call or retry can repair a later blur here.
    const initiallyFocused = editorAppeared && await note.evaluate((element) => {
      const owns = (node) => node === element || element.contains(node);
      // If first focus already came and went, type now: waiting for another
      // focus would conceal the very blur this test is meant to expose.
      if (window.noteFocusedElements.has(element) || owns(document.activeElement)) return true;
      return new Promise((resolve) => {
        const finish = (focused) => {
          document.removeEventListener('focusin', onFocus, true);
          clearTimeout(timer);
          resolve(focused);
        };
        const onFocus = (event) => { if (owns(event.target)) finish(true); };
        const timer = setTimeout(() => finish(false), 1000);
        document.addEventListener('focusin', onFocus, true);
      });
    });
    assert.ok(initiallyFocused, 'Initial editor focus prerequisite: the selected note must focus before typing');
    // Type without a field tap, then continue after the observed deferred
    // semantics blur window. A partial prefix is also a failure.
    const expected = scenario === 'reopen-preview' ? `saved${cycle}-moretail` : `note${cycle}tail`;
    // ArrowRight collapses any select-all selection to its end. Unlike End,
    // it cannot scroll the recipient list when typing focus is missing.
    if (scenario === 'reopen-preview') await page.keyboard.press('ArrowRight');
    await page.keyboard.type(scenario === 'reopen-preview' ? '-more' : `note${cycle}`, { delay: 30 });
    await page.waitForTimeout(350);
    await page.keyboard.type('tail', { delay: 30 });
    await page.waitForTimeout(400);
    const mounted = await note.count() === 1;
    const actual = mounted ? await note.inputValue() : null;
    const trace = await page.evaluate(() => window.noteFocusTrace);
    const geometry = await page.evaluate(() => {
      window.noteRevealGeometry.stopped = true;
      return window.noteRevealGeometry;
    });
    const revealDistance = geometry.initial - geometry.minimum;
    const revealObserved = revealDistance > 1;
    // Diagnostic observations only: CanvasKit/semantics may reveal through
    // Flutter geometry changes and may not emit DOM input focus events.
    // Correct typing and the same recipient's saved preview determine PASS.
    const autoFocused = trace.some(({ type, tag }) =>
      type === 'focusin' && ['INPUT', 'TEXTAREA'].includes(tag));
    const revealScrolled = trace.some(({ type }) => type === 'scroll');
    await tap(outside);
    await page.waitForTimeout(300);
    const keptPreview = !!await previewOnRecipientRow(chosen.checkbox, expected);
    const collapsed = await note.count() === 0;
    const checkboxAfter = await chosen.checkbox.boundingBox();
    const result = { scenario, cycle, userId, recipientName, spaceBelowRow,
      expected, actual, editorAppeared, autoFocused, revealScrolled,
      revealDistance, revealObserved,
      rowDisplacement: checkboxAfter ? checkboxAfter.y - chosen.box.y : null,
      keptPreview, collapsed, trace };
    results.push(result);
    console.log(JSON.stringify(result));
    if (needsReveal && !revealObserved) {
      // An absent initial focus request can prevent caret reveal entirely.
      // That is a prerequisite failure, not evidence of a post-reveal blur.
      // Stop instead of counting it as one of the required ten repetitions.
      throw new Error('SCROLL_REVEAL_BLOCKED: opening the lowest note did not move '
        + 'its row within the list; the diagnosed reveal-scroll sequence was not reached. '
        + `Editor appeared: ${editorAppeared}; retained text: ${JSON.stringify(actual)}. `
        + 'Check the descendant-focus prerequisite before claiming a scroll-reveal regression.');
    }
  }
  const failures = results.filter(({ actual, expected, keptPreview, collapsed }) =>
    actual !== expected || !keptPreview || !collapsed);
  console.log(`${failures.length ? 'FAIL' : 'PASS'} ${scenario}: ${failures.length}/${cycles} cycles lost the note or its preview`);
  process.exitCode = failures.length ? 2 : 0;
} catch (error) {
  console.error(error);
  if (page) console.error('Setup diagnostics:', await page.locator('body').innerText());
  // Setup failures never count as evidence of the missing behavior.
  process.exitCode = 1;
} finally {
  try { await deleteRequest?.(); } catch (error) {
    console.error('Request fixture cleanup failed:', error);
    process.exitCode = 1;
  }
  await browser?.close();
}
