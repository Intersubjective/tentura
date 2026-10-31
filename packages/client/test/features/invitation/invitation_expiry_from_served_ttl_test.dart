// The invitation lifetime is a server setting, so the pending-invitation list
// must cut off at the TTL the server serves, not at the compiled default.
// Runs the real `InvitationRepository` over the real `RemoteApiService` and
// Ferry link chain (only the HTTP transport is faked).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _emptyInvitations() => {
  '__typename': 'query_root',
  'pending': <Map<String, dynamic>>[],
  'accepted': <Map<String, dynamic>>[],
  'pending_count': {
    '__typename': 'invitation_aggregate',
    'aggregate': {'__typename': 'invitation_aggregate_fields', 'count': 0},
  },
};

/// How far back from now the pending list reaches, as sent on the wire.
Future<Duration> _pendingWindow({required int servedHours}) async {
  final sent = <WireSent>[];
  late DateTime before;
  late DateTime after;
  await withRemoteWire(
    {
      'InvitationTtl': {
        '__typename': 'query_root',
        'invitationTtlHours': servedHours,
      },
      'InvitationsFetchByUserId': _emptyInvitations(),
    },
    sent,
    (remote) async {
      before = DateTime.now().toUtc();
      await InvitationRepository(remote).fetchMine();
      after = DateTime.now().toUtc();
    },
  );
  final fetch = sent.singleWhere(
    (s) => s.operationName == 'InvitationsFetchByUserId',
  );
  final cutoff = DateTime.parse(fetch.variables['created_at_gt'] as String);
  // The cutoff was taken somewhere inside [before, after]; report the window
  // relative to the midpoint so a few ms of test runtime don't matter.
  final mid = before.add(after.difference(before) ~/ 2);
  return mid.difference(cutoff);
}

void main() {
  group('pending invitation list cutoff', () {
    test('follows the TTL the server serves', () async {
      final window = await _pendingWindow(servedHours: 48);
      expect(window.inMinutes, closeTo(48 * 60, 1));
    });

    test('follows a different served TTL, not a fixed one', () async {
      final window = await _pendingWindow(servedHours: 500);
      expect(window.inMinutes, closeTo(500 * 60, 1));
    });

    test(
      'differs from the compiled default when the server overrides it',
      () async {
        final window = await _pendingWindow(
          servedHours: kInvitationDefaultTTL * 2,
        );
        expect(window.inHours, isNot(kInvitationDefaultTTL));
      },
    );
  });
}
