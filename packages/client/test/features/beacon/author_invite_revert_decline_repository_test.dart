// The real `AuthorInviteRepository` over the real `RemoteApiService` and Ferry
// link chain: taking back a «Can't make it» sends the invite id to the revert
// mutation and maps the invitation that is pending again; a refusal arrives as
// the same typed exceptions the other invitation transitions throw.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';

import '../../support/remote_wire_harness.dart';

const _beaconId = 'Bchild0000001';
const _inviteId = 'Ainvite000001';

void main() {
  test('reverting a decline sends the invite id and maps the invitation '
      'that is pending again', () async {
    final sent = <WireSent>[];
    late AuthorInvite result;
    await withRemoteWire(
      {
        'AuthorInviteRevertDecline': {
          '__typename': 'mutation_root',
          'beaconAuthorInviteRevertDecline': {
            '__typename': 'AuthorInviteResult',
            'inviteId': _inviteId,
            'beaconId': _beaconId,
            'status': 'pending',
          },
        },
      },
      sent,
      (remote) async {
        result = await AuthorInviteRepository(
          remote,
        ).revertDecline(inviteId: _inviteId);
      },
    );

    expect(sent.single.operationName, 'AuthorInviteRevertDecline');
    expect(sent.single.variables, {'inviteId': _inviteId});
    expect(
      result,
      const AuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        status: AuthorInviteStatus.pending,
      ),
    );
  });

  test('a refused revert (invitation replaced or Request closed) throws the '
      'typed invitation exception', () async {
    final sent = <WireSent>[];
    Object? thrown;
    await withRemoteWire(
      const {},
      sent,
      (remote) async {
        try {
          await AuthorInviteRepository(
            remote,
          ).revertDecline(inviteId: _inviteId);
        } on Object catch (e) {
          thrown = e;
        }
      },
      errors: {
        'AuthorInviteRevertDecline': wireCodeError(1334),
      },
    );

    expect(sent.single.operationName, 'AuthorInviteRevertDecline');
    expect(thrown, isA<AuthorInviteNotPendingException>());
  });
}
