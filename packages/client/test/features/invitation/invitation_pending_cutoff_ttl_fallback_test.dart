// The pending-invitation list cuts off at the TTL the server serves. When the
// server cannot say (lookup fails or answers nothing), the list must still
// load, cut off at the compiled default, instead of failing with the lookup.
// Runs the real `InvitationRepository` over the real `RemoteApiService` and
// Ferry link chain (only the HTTP transport is faked).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _pendingInvitation() => {
  '__typename': 'invitation',
  'id': 'Iabc123def456',
  'beacon_id': null,
  'invited_id': null,
  'addressee_name': 'Clara',
  'invite_origin': null,
  'accepted_at': null,
  'created_at': '2026-10-30T00:00:00+00:00',
  'updated_at': '2026-10-30T00:00:00+00:00',
  'invited': null,
  'beacon': null,
};

Map<String, dynamic> _invitations() => {
  '__typename': 'query_root',
  'pending': [_pendingInvitation()],
  'accepted': <Map<String, dynamic>>[],
  'pending_count': {
    '__typename': 'invitation_aggregate',
    'aggregate': {'__typename': 'invitation_aggregate_fields', 'count': 1},
  },
};

typedef _Outcome = ({InvitationsFetchResult result, Duration window});

/// Loads the pending list while the TTL lookup misbehaves as configured, and
/// reports the list plus how far back its cutoff reached on the wire.
Future<_Outcome> _loadPending({
  Map<String, Map<String, dynamic>> responses = const {},
  Map<String, Map<String, dynamic>> errors = const {},
}) async {
  final sent = <WireSent>[];
  late InvitationsFetchResult result;
  late DateTime before;
  late DateTime after;
  await withRemoteWire(
    {'InvitationsFetchByUserId': _invitations(), ...responses},
    sent,
    (remote) async {
      before = DateTime.now().toUtc();
      result = await InvitationRepository(remote).fetchMine();
      after = DateTime.now().toUtc();
    },
    errors: errors,
  );
  final fetch = sent.singleWhere(
    (s) => s.operationName == 'InvitationsFetchByUserId',
  );
  final cutoff = DateTime.parse(fetch.variables['created_at_gt'] as String);
  final mid = before.add(after.difference(before) ~/ 2);
  return (result: result, window: mid.difference(cutoff));
}

void main() {
  group('pending invitation list when the served TTL is unavailable', () {
    test('still loads, cut off at the compiled default, when the server '
        'answers the TTL lookup with an error', () async {
      final outcome = await _loadPending(
        errors: {'InvitationTtl': wireCodeError(1)},
      );
      expect(outcome.result.pending.map((i) => i.id), ['Iabc123def456']);
      expect(outcome.result.pendingCount, 1);
      expect(outcome.window.inMinutes, closeTo(kInvitationDefaultTTL * 60, 1));
    });

    test('still loads, cut off at the compiled default, when the server '
        'answers the TTL lookup with no data', () async {
      final outcome = await _loadPending();
      expect(outcome.result.pending.map((i) => i.id), ['Iabc123def456']);
      expect(outcome.window.inMinutes, closeTo(kInvitationDefaultTTL * 60, 1));
    });

    test('uses the served TTL, not the default, when the lookup succeeds', () async {
      final outcome = await _loadPending(
        responses: {
          'InvitationTtl': {
            '__typename': 'query_root',
            'invitationTtlHours': 48,
          },
        },
      );
      expect(outcome.result.pending, hasLength(1));
      expect(outcome.window.inMinutes, closeTo(48 * 60, 1));
    });
  });
}
