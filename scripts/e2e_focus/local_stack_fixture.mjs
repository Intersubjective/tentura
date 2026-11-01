// Own only the missing local processes; Docker services are shared prerequisites.
import { spawn } from 'node:child_process';
import { openSync, closeSync, mkdtempSync } from 'node:fs';
import { get as httpGet } from 'node:http';
import { get as httpsGet } from 'node:https';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const base = process.env.BASE || 'https://dev.lvh.me:9443';
const owned = [];
const logs = mkdtempSync(resolve(tmpdir(), 'tentura-focus-stack-'));
const reachable = (url) => new Promise((done) => {
  const request = (url.startsWith('https:') ? httpsGet : httpGet)(url, {
    rejectUnauthorized: false, timeout: 1000,
  }, (response) => { response.resume(); done(response.statusCode === 200); });
  request.on('error', () => done(false));
  request.on('timeout', () => { request.destroy(); done(false); });
});
function start(name, command, args, env = {}) {
  const fd = openSync(resolve(logs, `${name}.log`), 'w');
  const child = spawn(command, args, {
    cwd: root, env: { ...process.env, ...env }, detached: true,
    stdio: ['ignore', fd, fd],
  });
  closeSync(fd);
  child.on('error', (error) => console.error(`${name}: ${error.message}`));
  owned.push(child);
  return child;
}
async function ready(url, child) {
  for (let attempt = 0; attempt < 60; attempt++) {
    if (await reachable(url)) return;
    if (child.exitCode !== null) break;
    await new Promise((done) => setTimeout(done, 1000));
  }
  throw new Error(`Local stack prerequisite unavailable: ${url}; logs: ${logs}`);
}
function stop() {
  for (const child of owned.reverse()) {
    try { process.kill(-child.pid, 'SIGTERM'); } catch { /* Already stopped. */ }
  }
}
process.on('SIGTERM', () => { stop(); process.exit(143); });
process.on('SIGINT', () => { stop(); process.exit(130); });
try {
  // Remote origins must already provide their own API and profile build.
  if (!process.env.BASE) {
    if (!await reachable('http://127.0.0.1:2080/health')) {
      await ready('http://127.0.0.1:2080/health', start('api', 'bash', ['scripts/run-server-local.sh']));
    }
    if (!await reachable(`${base}/`)) {
      await ready(`${base}/`, start('caddy', 'caddy', ['run', '--config', 'Caddyfile.local'], {
        LOCAL_USE_FLUTTER_PROXY: 'off',
        LOCAL_APP_ROOT: process.env.FOCUS_WEB_DIR || '/tmp/tentura-focus-profile-web',
      }));
    }
  }
  const [mode = 'all', ...args] = process.argv.slice(2);
  const target = mode === 'all'
    ? ['scripts/e2e_focus/typing_survives_interactions_on_all_surfaces.mjs', ...args]
    : mode === 'scroll-reveal'
      ? ['scripts/e2e_focus/typing_survives_note_reveal_scroll.mjs', ...args]
      : ['scripts/e2e_focus/typing_survives_clear_and_tooltip.mjs', mode, ...args];
  const suite = spawn(process.execPath, [
    ...target,
  ], { cwd: root, stdio: 'inherit', env: process.env });
  process.exitCode = await new Promise((done, reject) => {
    suite.on('error', reject);
    suite.on('exit', (code) => done(code ?? 1));
  });
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  stop();
}
