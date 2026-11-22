// Node resolves an explicit test directory to index.js. Run each suite in
// isolation because the landing browser fakes install globals.
const { spawnSync } = require('node:child_process');
const { readdirSync } = require('node:fs');
const { join } = require('node:path');

const suites = readdirSync(__dirname)
  .filter((file) => file.endsWith('_test.mjs'))
  .sort()
  .map((file) => join(__dirname, file));
if (suites.length === 0) throw new Error('No landing test suites found');

// Start a fresh runner, not a recursive run inside the outer test worker.
const env = { ...process.env };
delete env.NODE_TEST_CONTEXT;
const result = spawnSync(process.execPath, ['--test', ...suites], { env, stdio: 'inherit' });
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
