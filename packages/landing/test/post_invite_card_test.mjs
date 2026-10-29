// #520: the invite landing card for a Post invite shows the Post excerpt the
// preview endpoint now returns. Same helpers main.js renders the card with.
import test from 'node:test';
import assert from 'node:assert/strict';

import { needsExpand, beaconBodyText } from '../beacon_overlay.js';

const text = 'Q520 post: community garden cleanup…';

test('a post invite card shows the post excerpt as its collapsed body', () => {
  const beacon = {
    id: 'Bpost',
    kind: 'post',
    title: '',
    snippet: text,
    description: text,
  };
  assert.equal(beaconBodyText(beacon, false), text);
  assert.equal(needsExpand(beacon.snippet, beacon.description), false);
});

test('a long post excerpt is clipped when collapsed and full when expanded', () => {
  const full = `${text} ${'garden cleanup '.repeat(20)}`.trim();
  const beacon = {
    kind: 'post',
    title: '',
    snippet: `${full.slice(0, 140)}…`,
    description: full,
  };
  assert.equal(beaconBodyText(beacon, false), beacon.snippet);
  assert.equal(beaconBodyText(beacon, true), full);
  assert.equal(needsExpand(beacon.snippet, beacon.description), true);
});
