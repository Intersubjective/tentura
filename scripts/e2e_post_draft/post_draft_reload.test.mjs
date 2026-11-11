// Production Post composer -> real HTTP/Ferry -> an isolated server fixture ->
// a new browser document -> production loadDraft and attachment strip.
// Run this file only, through scripts/run_with_test_cleanup.sh.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { before, after, test } from 'node:test';

// Reuse the existing browser harness dependency installation.
const require = createRequire(new URL('../e2e_session_account/package.json', import.meta.url));
const { chromium } = require('playwright');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const id = 'Bpostreload01';
const requests = [];
const draft = { body: '', policy: 1, lifetime: 72, attachments: [] };
let server, browser, origin, webDir;
let documentLoads = 0;

function beacon() {
  return {
    __typename: 'beacon', id, title: '', description: draft.body, kind: 1,
    forward_policy: draft.policy, post_lifetime_hours: draft.lifetime,
    post_draft_attachments: draft.attachments.map(({ bytes, ...row }) => row),
    cover_source: 0, needs: '', tags: '', status: 3,
    created_at: '2026-11-09T12:00:00Z', updated_at: '2026-11-09T12:00:00Z',
    is_discoverable: false, beacon_images: [], active_help_offers: [],
    participant_help_offers: [], admitted_helpers: [],
    author: { __typename: 'user', id: 'Uviewer000001', display_name: 'Олег', description: '', scores: [] },
    help_offers_aggregate: { __typename: 'beacon_help_offer_aggregate', aggregate: null },
    unanswered_help_offers: { __typename: 'beacon_help_offer_aggregate', aggregate: null },
    admitted_helpers_aggregate: { __typename: 'beacon_admitted_helper_aggregate', aggregate: null },
  };
}

before(async () => {
  webDir = await mkdtemp(join(tmpdir(), 'tentura-post-draft-reload-'));
  server = createServer(async (request, response) => {
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      const json = (body) => {
        response.setHeader('Content-Type', 'application/json');
        response.end(JSON.stringify(body));
      };
      if (/\/graphql$/.test(path)) {
        const chunks = [];
        for await (const chunk of request) chunks.push(chunk);
        const raw = Buffer.concat(chunks).toString('utf8');
        const multipart = request.headers['content-type']?.startsWith('multipart/');
        const operation = JSON.parse(multipart
          ? /name="operations"\r\n\r\n(.*?)\r\n--/s.exec(raw)[1] : raw);
        const { operationName: name, variables: vars } = operation;
        requests.push({ name, vars, document: documentLoads });
        let data;
        switch (name) {
          case 'BeaconCreate':
            assert.equal(vars.kind, 1);
            assert.equal(vars.draft, true);
            data = { beaconCreate: { __typename: 'v2_Beacon', id } };
            break;
          case 'BeaconFetchById':
            assert.equal(vars.id, id);
            data = { beacon_by_pk: beacon() };
            break;
          case 'PostUpdateDraft':
            assert.equal(vars.beaconId ?? vars.id, id);
            Object.assign(draft, { body: vars.body, policy: vars.forwardPolicy, lifetime: vars.lifetimeHours });
            data = { postUpdateDraft: { __typename: 'v2_Beacon', id } };
            break;
          case 'PostDraftAttachmentAdd': {
            assert.equal(vars.draftBeaconId ?? vars.beaconId, id);
            assert.equal(multipart, true, 'The picked file is a real multipart upload');
            const boundary = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(request.headers['content-type']);
            assert.ok(boundary, 'The multipart request declares its boundary');
            const part = raw.split(`--${boundary[1] ?? boundary[2]}`)
              .find((section) => /content-disposition:[^\r\n]*filename=/i.test(section));
            assert.ok(part, 'The request contains the picked file part');
            const separator = part.indexOf('\r\n\r\n');
            assert.ok(separator >= 0, 'The file part separates headers from bytes');
            const headers = part.slice(0, separator);
            const filename = /filename="([^"]+)"/i.exec(headers);
            const mime = /content-type: ([^\r\n]+)/i.exec(headers);
            assert.ok(filename, 'The picked file keeps its filename');
            assert.ok(mime, 'The picked file keeps its MIME type');
            const bytes = Buffer.from(part.slice(separator + 4, -2));
            assert.equal(filename[1], 'notes.txt');
            assert.equal(mime[1], 'text/plain');
            assert.equal(bytes.toString('utf8'), 'draft attachment');
            const attachmentId = `Adraftfile00${draft.attachments.length}`;
            draft.attachments.push({ __typename: 'post_draft_attachment', id: attachmentId,
              beacon_id: id, kind: 2, position: draft.attachments.length,
              file_name: filename[1], mime: mime[1], bytes,
              size_bytes: bytes.length, file_url: `${origin}/attachments/${attachmentId}`,
              image_id: null, image: null, width: null, height: null });
            data = { postDraftAttachmentAdd: attachmentId };
            break;
          }
          default: throw new Error(`Unexpected GraphQL operation ${name}`);
        }
        json({ data });
      } else if (path.startsWith('/attachments/')) {
        const attachment = draft.attachments.find((a) => a.file_url.endsWith(path));
        assert.ok(attachment, 'Only saved attachments can be downloaded');
        response.setHeader('Content-Type', attachment.mime);
        response.end(attachment.bytes);
      } else if (path === '/' || path === '/post/new') {
        documentLoads++;
        response.setHeader('Content-Type', 'text/html');
        response.end('<!doctype html><html><head><base href="/"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><script src="flutter_bootstrap.js" async></script></body></html>');
      } else {
        const file = resolve(webDir, `.${path}`);
        if (!file.startsWith(`${resolve(webDir)}/`)) return response.writeHead(403).end();
        response.setHeader('Content-Type', { '.wasm': 'application/wasm', '.js': 'text/javascript',
          '.mjs': 'text/javascript', '.json': 'application/json', '.woff2': 'font/woff2' }[extname(path)] || 'application/octet-stream');
        try { response.end(await readFile(file)); }
        catch { response.writeHead(404).end(); }
      }
    } catch (error) {
      console.error('Post draft HTTP fixture:', error);
      response.writeHead(500).end(String(error));
    }
  });
  await new Promise((ready) => server.listen(0, '127.0.0.1', ready));
  origin = `http://127.0.0.1:${server.address().port}`;
  const sdk = process.env.FLUTTER_ROOT;
  const command = sdk ? join(sdk, 'bin/cache/dart-sdk/bin/dart') : 'flutter';
  const args = sdk
    ? [join(sdk, 'bin/cache/flutter_tools.snapshot'), '--no-version-check', '--suppress-analytics'] : [];
  args.push('build', 'web', '--wasm', '--no-pub', '--no-web-resources-cdn',
    '--target=integration_test/support/post_draft_reload_browser_app.dart',
    `--output=${webDir}`, `--dart-define=SERVER_NAME=${origin}`);
  await new Promise((done, reject) => {
    const build = spawn(command, args, { cwd: join(root, 'packages/client'), stdio: 'inherit',
      timeout: 480000, killSignal: 'SIGKILL', env: { ...process.env, FLUTTER_ALREADY_LOCKED: 'true',
        FLUTTER_SUPPRESS_ANALYTICS: 'true', DASH__SUPPRESS_ANALYTICS: 'true' } });
    build.on('error', reject);
    build.on('exit', (code) => code === 0 ? done() : reject(new Error(`Flutter build exited ${code}`)));
  });
  browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox'] });
}, { timeout: 600000 });

after(async () => {
  await browser?.close();
  if (server) {
    server.closeAllConnections();
    await new Promise((done) => server.close(done));
  }
  if (webDir) await rm(webDir, { recursive: true, force: true });
});

test('a Post draft restores body file closed forwarding and 24 hour lifetime after a document reload', { timeout: 90000 }, async (t) => {
  const context = await browser.newContext({ viewport: { width: 1280, height: 1024 } });
  t.after(() => context.close());
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', (error) => errors.push(String(error)));
  await page.goto(`${origin}/post/new`);
  await page.waitForFunction(() => typeof window.postDraftComposerSnapshot === 'function');
  const body = 'Server-owned Post draft survives a real document reload.';
  await page.getByRole('textbox').fill(body);
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Файлы', exact: true }).click();
  await (await chooser).setFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('draft attachment') });
  await page.getByRole('switch').click();
  await page.getByRole('button', { name: '24 часа', exact: true }).click();
  await page.waitForFunction(() => {
    const s = JSON.parse(window.postDraftComposerSnapshot());
    return s.files.length === 1 && s.canForward === false && s.lifetimeHours === 24 && s.draftId;
  });
  await page.waitForTimeout(1800); // Let the last setting's 1.5 s autosave settle.
  const before = await snapshot(page);
  assert.deepEqual({ body: before.body, files: before.files, canForward: before.canForward, lifetimeHours: before.lifetimeHours },
    { body, files: ['notes.txt'], canForward: false, lifetimeHours: 24 }, 'The real composer accepted every input before reload');
  assert.deepEqual(errors, []);
  assert.deepEqual(before.errors, []);

  const firstDocument = await page.evaluate(() => performance.timeOrigin);
  await page.evaluate((id) => {
    window.history.replaceState(null, '', `/post/new?draft_id=${id}`);
    window.__postDraftOldDocument = true;
  }, before.draftId);
  await page.reload();
  await page.waitForFunction(() => typeof window.postDraftComposerSnapshot === 'function');
  await page.waitForFunction(() => {
    const s = JSON.parse(window.postDraftComposerSnapshot());
    return s.draftId && Object.hasOwn(s, 'lifetimeHours') && Object.hasOwn(s, 'canForward');
  });
  assert.ok(await page.evaluate(() => performance.timeOrigin) > firstDocument, 'Reload must create a fresh browser document');
  assert.equal(await page.evaluate(() => Boolean(window.__postDraftOldDocument)), false);
  assert.equal(documentLoads, 2);
  assert.match(page.url(), new RegExp(`/post/new\\?draft_id=${id}$`));
  assert.ok(requests.some((r) => r.name === 'BeaconFetchById' && r.document === 2), 'The new document must fetch the server draft');
  const restored = await snapshot(page);
  assert.deepEqual({ body: restored.body, files: restored.files, canForward: restored.canForward, lifetimeHours: restored.lifetimeHours },
    { body, files: ['notes.txt'], canForward: false, lifetimeHours: 24 },
    'Reload must restore body, saved file in PendingAttachmentPreview, closed forwarding and 24 hours from the server draft');
  assert.deepEqual(errors, []);
  assert.deepEqual(restored.errors, []);
  assert.equal(requests.some((r) => r.name === 'PostPublish'), false, 'Draft reload never publishes');
});

async function snapshot(page) {
  return page.evaluate(() => JSON.parse(window.postDraftComposerSnapshot()));
}
