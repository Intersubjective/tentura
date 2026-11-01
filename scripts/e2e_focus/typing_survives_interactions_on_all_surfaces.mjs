// Browser acceptance matrix: every surface of the #603 sibling matrix.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const cycles = Number(process.argv[2] || 10);
assert.ok(Number.isInteger(cycles) && cycles >= 10, 'Every surface requires at least ten cycles');
const forward = {
  ROUTE: '/#/forward/{requestId}', FIELD_LABEL: 'search recipients',
  CLEAR_LABEL: 'Cancel', PRE_CLICK_LABEL: 'search recipients',
};
const chat = {
  ROUTE: '/#/beacon/view/{requestId}?tab=threads&thread=general',
  FIELD_LABEL: 'Write a message…', RESET_XY: '1270,400',
};
const scenarios = [
  { name: 'Rating search keeps typing after clear', mode: 'close', env: {} },
  { name: 'Rating search keeps typing across tooltip transitions', mode: 'hover', env: {} },
  {
    name: 'Updates search keeps typing after clear', mode: 'close',
    env: { ROUTE: '/#/home/updates', FIELD_LABEL: 'Search updates', CLEAR_LABEL: 'Clear search', RESET_XY: '1270,790' },
  },
  { name: 'Forward recipient search keeps typing after clear', mode: 'close', env: forward },
  { name: 'Forward recipient search keeps typing across tooltip transitions', mode: 'hover', env: forward },
  { name: 'Chat composer keeps typing across Emoji tooltip transitions', mode: 'hover', env: { ...chat, HOVER_LABEL: 'Emoji' } },
  { name: 'Chat composer keeps typing across Back tooltip transitions', mode: 'hover', env: { ...chat, HOVER_LABEL: 'Back' } },
];

const results = [];
for (const scenario of scenarios) {
  // An inherited per-screen override must never replace a selected row.
  const env = { ...process.env };
  for (const key of ['ROUTE', 'FIELD_LABEL', 'CLEAR_LABEL', 'HOVER_LABEL', 'PRE_CLICK_LABEL', 'RESET_XY']) delete env[key];
  Object.assign(env, scenario.env);
  console.log(`SCENARIO ${scenario.name} (${cycles} cycles)`);
  const child = spawn(process.execPath, [
    'scripts/e2e_focus/typing_survives_clear_and_tooltip.mjs', scenario.mode, String(cycles),
  ], { cwd: root, env, stdio: 'inherit' });
  const code = await new Promise((done) => {
    child.on('error', (error) => { console.error(error); done(1); });
    child.on('exit', (exitCode) => done(exitCode ?? 1));
  });
  results.push({ name: scenario.name, cycles, exitCode: code });
  // Complete the selected matrix even when an earlier row fails.
}
console.log('ACCEPTANCE MATRIX', JSON.stringify(results));
// Setup errors cannot be reported as evidence of missing typing behavior.
process.exitCode = results.some(({ exitCode }) => exitCode !== 0 && exitCode !== 2)
  ? 1 : results.some(({ exitCode }) => exitCode === 2) ? 2 : 0;
