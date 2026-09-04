import test from 'node:test';
import assert from 'node:assert/strict';

import { needsExpand, beaconBodyText } from '../beacon_overlay.js';

test('needsExpand is false when text fits in the snippet', () => {
  assert.equal(needsExpand('short request', 'short request'), false);
  assert.equal(needsExpand('same', 'same'), false);
});

test('needsExpand is true when description is longer than snippet', () => {
  const snippet = `${'a'.repeat(140)}…`;
  const description = `${'a'.repeat(140)} and the rest of the request`;
  assert.equal(needsExpand(snippet, description), true);
});

test('needsExpand is false without snippet or description', () => {
  assert.equal(needsExpand('', 'full text only'), false);
  assert.equal(needsExpand('snippet only', ''), false);
  assert.equal(needsExpand(null, null), false);
  assert.equal(needsExpand(undefined, undefined), false);
});

test('beaconBodyText prefers snippet when collapsed', () => {
  assert.equal(
    beaconBodyText(
      { snippet: 'short…', description: 'short and then more detail' },
      false,
    ),
    'short…',
  );
});

test('beaconBodyText uses full description when expanded', () => {
  assert.equal(
    beaconBodyText(
      { snippet: 'short…', description: 'short and then more detail' },
      true,
    ),
    'short and then more detail',
  );
});

test('beaconBodyText falls back to description when snippet missing', () => {
  assert.equal(
    beaconBodyText({ description: 'only full text' }, false),
    'only full text',
  );
});
