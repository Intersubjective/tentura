import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseInviteEntryInput,
  invitePathForCode,
  INVITE_CODE_PATTERN,
  normalizeInviteCode,
  inviteCodeHadTrailingDash,
} from '../invite_entry.js';

test('INVITE_CODE_PATTERN rejects bare I', () => {
  assert.equal(INVITE_CODE_PATTERN.test('I'), false);
  assert.equal(INVITE_CODE_PATTERN.test('Iabc'), true);
});

test('parseInviteEntryInput accepts raw code', () => {
  const result = parseInviteEntryInput('  Iabc123  ');
  assert.equal(result.ok, true);
  assert.equal(result.code, 'Iabc123');
});

test('parseInviteEntryInput accepts code with trailing dash', () => {
  const result = parseInviteEntryInput('I806d29daebbe-');
  assert.equal(result.ok, true);
  assert.equal(result.code, 'I806d29daebbe');
});

test('parseInviteEntryInput accepts full invite URL', () => {
  const result = parseInviteEntryInput(
    'https://dev.lvh.me:9443/invite/Ideadbeef?x=1',
  );
  assert.equal(result.ok, true);
  assert.equal(result.code, 'Ideadbeef');
});

test('parseInviteEntryInput accepts /invite/ path', () => {
  const result = parseInviteEntryInput('/invite/Iabc');
  assert.equal(result.ok, true);
  assert.equal(result.code, 'Iabc');
});

test('parseInviteEntryInput rejects invalid code', () => {
  const result = parseInviteEntryInput('not-an-invite');
  assert.equal(result.ok, false);
});

test('parseInviteEntryInput rejects empty input', () => {
  const result = parseInviteEntryInput('   ');
  assert.equal(result.ok, false);
});

test('invitePathForCode encodes code in path', () => {
  assert.equal(invitePathForCode('Iabc'), '/invite/Iabc');
});

test('normalizeInviteCode strips trailing dash', () => {
  assert.equal(normalizeInviteCode('I806d29daebbe-'), 'I806d29daebbe');
});

test('parseInviteEntryInput accepts code with trailing dash', () => {
  const result = parseInviteEntryInput('I806d29daebbe-');
  assert.equal(result.ok, true);
  assert.equal(result.code, 'I806d29daebbe');
});

test('inviteCodeHadTrailingDash detects paste typo', () => {
  assert.equal(inviteCodeHadTrailingDash('Iabc-'), true);
  assert.equal(inviteCodeHadTrailingDash('Iabc'), false);
});
