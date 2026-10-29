// Runs only the native-browser Field touch regression. Requires Node 22+,
// Flutter and Chrome (CHROME_EXECUTABLE overrides google-chrome). This is an
// explicit browser run; the @TestOn('browser') file is not a VM bundle test.
import { createServer } from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const client = fileURLToPath(new URL('../../../', import.meta.url));
const chrome = process.env.CHROME_EXECUTABLE || 'google-chrome';
const preflight = spawnSync(chrome, ['--version'], { encoding: 'utf8' });
if (preflight.error || preflight.status !== 0) {
  throw new Error(`Browser prerequisite unavailable: ${chrome}; set CHROME_EXECUTABLE`);
}
console.log(`Browser prerequisite: ${preflight.stdout.trim()}`);
const temporary = await mkdtemp(join(tmpdir(), 'field-native-touch-'));
const portFile = join(temporary, 'chrome-port');
const wrapper = join(temporary, 'chrome');
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
await writeFile(wrapper, `#!/bin/sh
for argument in "$@"; do
  case "$argument" in
    --remote-debugging-port=*) printf '%s' "\${argument#*=}" > ${quote(portFile)} ;;
  esac
done
exec ${quote(chrome)} "$@" --no-sandbox
`, { mode: 0o700 });
let socket;
let nextId = 0;
const pending = new Map();
async function cdp(method, params = {}) {
  const id = ++nextId;
  const promise = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  socket.send(JSON.stringify({ id, method, params }));
  return await promise;
}
async function connect() {
  if (socket) return;
  const port = (await readFile(portFile, 'utf8')).trim();
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find(target => target.type === 'page');
  if (!page) throw new Error('Flutter test Chrome has no page target');
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', event => {
    const result = JSON.parse(event.data);
    if (result.method === 'Runtime.consoleAPICalled') {
      console.log(...result.params.args.map(arg => arg.value ?? arg.description ?? ''));
    }
    if (result.method === 'Runtime.exceptionThrown') {
      console.error(JSON.stringify(result.params.exceptionDetails));
    }
    const request = pending.get(result.id);
    if (!request) return;
    pending.delete(result.id);
    if (result.error) request.reject(new Error(JSON.stringify(result.error)));
    else request.resolve(result.result);
  });
  await cdp('Runtime.enable');
}
const broker = createServer(async (request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Headers', 'content-type');
  response.setHeader('Access-Control-Allow-Private-Network', 'true');
  if (request.method === 'OPTIONS') { response.end(); return; }
  try {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const input = JSON.parse(Buffer.concat(chunks).toString());
    await connect();
    if (input.configure) {
      await cdp('Emulation.setDeviceMetricsOverride', {
        width: 375, height: 667, deviceScaleFactor: 2, mobile: true,
      });
      await cdp('Emulation.setTouchEmulationEnabled', { enabled: true });
      // package:test hides its iframe during automated runs. Expose that
      // same iframe for native input; leave Flutter's widget DOM untouched.
      await cdp('Runtime.evaluate', { expression: `
        document.head.insertAdjacentHTML('beforeend', '<meta name="viewport" content="width=device-width, initial-scale=1">');
        document.body.style.cssText = 'margin:0;overflow:hidden';
        for (const frame of document.querySelectorAll('iframe')) {
          frame.style.cssText = 'visibility:visible;position:fixed;left:0;top:0;width:375px;height:667px;border:0;z-index:10';
        }
      ` });
    } else if (input.kind === 'touch') {
      await cdp('Input.dispatchTouchEvent', {
        type: 'touchStart', touchPoints: [{ x: input.x, y: input.y, radiusX: 1, radiusY: 1 }],
      });
      await cdp('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    } else if (input.kind === 'mouse') {
      for (const type of ['mousePressed', 'mouseReleased']) {
        await cdp('Input.dispatchMouseEvent', {
          type, x: input.x, y: input.y, button: 'left', clickCount: 1,
        });
      }
    } else throw new Error(`Unknown native input: ${JSON.stringify(input)}`);
    response.end('{}');
  } catch (error) {
    response.statusCode = 500;
    response.end(String(error.stack || error));
  }
});
await new Promise(resolve => broker.listen(0, '127.0.0.1', resolve));
const brokerUrl = `http://127.0.0.1:${broker.address().port}`;
try {
  const flutter = spawn('flutter', [
    'test', '--no-pub', '--platform=chrome', '--reporter=expanded',
    '--dart-define=ENV=test', '--dart-define-from-file=env/test.env',
    `--dart-define=NATIVE_TOUCH_BROKER=${brokerUrl}`,
    'test/features/constellation/constellation_overlapping_dot_browser_touch_test.dart',
  ], { cwd: resolve(client), env: { ...process.env, CHROME_EXECUTABLE: wrapper }, stdio: 'inherit' });
  process.exitCode = await new Promise((resolve, reject) => {
    flutter.once('error', reject);
    flutter.once('exit', (code, signal) => resolve(code ?? (signal ? 1 : 0)));
  });
} finally {
  socket?.close();
  broker.closeAllConnections();
  broker.close();
  await rm(temporary, { recursive: true, force: true });
}
