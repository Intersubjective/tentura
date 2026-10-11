// Plan D0: the real `AuthorInviteRepository` over the real `RemoteApiService`
// and Ferry link chain. Pins the variables each author-invite operation sends,
// the mapping of their responses, and the typed exceptions for 1333-1335.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';

import '../../support/remote_wire_harness.dart';

const _beaconId = 'Bchild0000001';
const _inviteId = 'Ainvite000001';

Map<String, dynamic> _transition(String field, String status) => {
  '__typename': 'mutation_root',
  field: {
    '__typename': 'AuthorInviteResult',
    'inviteId': _inviteId,
    'beaconId': _beaconId,
    'status': status,
  },
};

void main() {
  test('create sends beaconId/userId/note and maps outcome + id', () async {
    final sent = <WireSent>[];
    final results = <AuthorInviteCreateResult>[];
    await withRemoteWire(
      {
        'AuthorInviteCreate': {
          '__typename': 'mutation_root',
          'beaconAuthorInviteCreate': {
            '__typename': 'AuthorInviteCreateResult',
            'outcome': 'invited',
            'inviteId': _inviteId,
          },
        },
      },
      sent,
      (remote) async {
        results.add(
          await AuthorInviteRepository(remote).create(
            beaconId: _beaconId,
            userId: 'Uinvitee00001',
            note: 'You know fences',
          ),
        );
      },
    );
    expect(sent.single.operationName, 'AuthorInviteCreate');
    expect(sent.single.variables, {
      'beaconId': _beaconId,
      'userId': 'Uinvitee00001',
      'note': 'You know fences',
    });
    expect(
      results.single,
      const AuthorInviteCreateResult(
        outcome: PostBudInviteOutcome.invited,
        inviteId: _inviteId,
      ),
    );
  });

  test('create maps a not-invited outcome without an id', () async {
    late AuthorInviteCreateResult result;
    await withRemoteWire(
      {
        'AuthorInviteCreate': {
          '__typename': 'mutation_root',
          'beaconAuthorInviteCreate': {
            '__typename': 'AuthorInviteCreateResult',
            'outcome': 'recipientPaused',
            'inviteId': null,
          },
        },
      },
      <WireSent>[],
      (remote) async {
        result = await AuthorInviteRepository(
          remote,
        ).create(beaconId: _beaconId, userId: 'Uinvitee00001');
      },
    );
    expect(result.outcome, PostBudInviteOutcome.recipientPaused);
    expect(result.inviteId, isNull);
  });

  test('accept / decline / withdraw send inviteId and map status', () async {
    final sent = <WireSent>[];
    final results = <AuthorInvite>[];
    await withRemoteWire(
      {
        'AuthorInviteAccept': _transition(
          'beaconAuthorInviteAccept',
          'accepted',
        ),
        'AuthorInviteDecline': _transition(
          'beaconAuthorInviteDecline',
          'declined',
        ),
        'AuthorInviteWithdraw': _transition(
          'beaconAuthorInviteWithdraw',
          'withdrawn',
        ),
      },
      sent,
      (remote) async {
        final repo = AuthorInviteRepository(remote);
        results
          ..add(await repo.accept(inviteId: _inviteId))
          ..add(await repo.decline(inviteId: _inviteId))
          ..add(await repo.withdraw(inviteId: _inviteId));
      },
    );
    expect(sent.map((s) => s.operationName), [
      'AuthorInviteAccept',
      'AuthorInviteDecline',
      'AuthorInviteWithdraw',
    ]);
    for (final s in sent) {
      expect(s.variables, {'inviteId': _inviteId});
    }
    expect(results, const [
      AuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        status: AuthorInviteStatus.accepted,
      ),
      AuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        status: AuthorInviteStatus.declined,
      ),
      AuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        status: AuthorInviteStatus.withdrawn,
      ),
    ]);
  });

  test('myPending maps the invitee projection', () async {
    final sent = <WireSent>[];
    late List<PendingAuthorInvite> invites;
    await withRemoteWire(
      {
        'MyPendingAuthorInvites': {
          '__typename': 'query_root',
          'myPendingAuthorInvites': [
            {
              '__typename': 'PendingAuthorInvite',
              'inviteId': _inviteId,
              'beaconId': _beaconId,
              'beaconTitle': 'Fix the fence',
              'inviterId': 'Uinviter00001',
              'sourcePostId': 'Bpost00000001',
              'note': 'You have a saw',
              'createdAt': '2026-10-11T08:30:00.000Z',
            },
            {
              '__typename': 'PendingAuthorInvite',
              'inviteId': 'Ainvite000002',
              'beaconId': 'Bchild0000002',
              'beaconTitle': 'Paint it',
              'inviterId': 'Uinviter00002',
              'sourcePostId': null,
              'note': null,
              'createdAt': '2026-10-11T09:00:00.000Z',
            },
          ],
        },
      },
      sent,
      (remote) async {
        invites = await AuthorInviteRepository(remote).myPending();
      },
    );
    expect(sent.single.operationName, 'MyPendingAuthorInvites');
    expect(invites, [
      PendingAuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        beaconTitle: 'Fix the fence',
        inviterId: 'Uinviter00001',
        sourcePostId: 'Bpost00000001',
        note: 'You have a saw',
        createdAt: DateTime.utc(2026, 10, 11, 8, 30),
      ),
      PendingAuthorInvite(
        id: 'Ainvite000002',
        beaconId: 'Bchild0000002',
        beaconTitle: 'Paint it',
        inviterId: 'Uinviter00002',
        createdAt: DateTime.utc(2026, 10, 11, 9),
      ),
    ]);
    expect(invites.first.createdAt.isUtc, isTrue);
  });

  test('beaconInvites sends beaconId and maps the author projection', () async {
    final sent = <WireSent>[];
    late List<AuthorInvite> invites;
    await withRemoteWire(
      {
        'BeaconAuthorInvites': {
          '__typename': 'query_root',
          'beaconAuthorInvites': [
            {
              '__typename': 'BeaconAuthorInvite',
              'inviteId': _inviteId,
              'inviteeId': 'Uinvitee00001',
              'status': 'pending',
              'note': 'You have a saw',
              'createdAt': '2026-10-11T08:30:00.000Z',
            },
            {
              '__typename': 'BeaconAuthorInvite',
              'inviteId': 'Ainvite000002',
              'inviteeId': 'Uinvitee00002',
              'status': 'superseded',
              'note': null,
              'createdAt': '2026-10-10T08:30:00.000Z',
            },
          ],
        },
      },
      sent,
      (remote) async {
        invites = await AuthorInviteRepository(
          remote,
        ).beaconInvites(beaconId: _beaconId);
      },
    );
    expect(sent.single.operationName, 'BeaconAuthorInvites');
    expect(sent.single.variables, {'beaconId': _beaconId});
    expect(invites, [
      AuthorInvite(
        id: _inviteId,
        beaconId: _beaconId,
        inviteeId: 'Uinvitee00001',
        status: AuthorInviteStatus.pending,
        note: 'You have a saw',
        createdAt: DateTime.utc(2026, 10, 11, 8, 30),
      ),
      AuthorInvite(
        id: 'Ainvite000002',
        beaconId: _beaconId,
        inviteeId: 'Uinvitee00002',
        status: AuthorInviteStatus.superseded,
        createdAt: DateTime.utc(2026, 10, 10, 8, 30),
      ),
    ]);
  });

  test('budObservers sends beaconId and maps the observer ids', () async {
    final sent = <WireSent>[];
    late List<String> observers;
    await withRemoteWire(
      {
        'BeaconBudObservers': {
          '__typename': 'query_root',
          'beaconBudObservers': ['Uobserver0001', 'Uobserver0002'],
        },
      },
      sent,
      (remote) async {
        observers = await AuthorInviteRepository(
          remote,
        ).budObservers(beaconId: _beaconId);
      },
    );
    expect(sent.single.operationName, 'BeaconBudObservers');
    expect(sent.single.variables, {'beaconId': _beaconId});
    expect(observers, ['Uobserver0001', 'Uobserver0002']);
  });

  group('typed errors', () {
    final cases = <int, Matcher>{
      1333: isA<AuthorInviteNotFoundException>(),
      1334: isA<AuthorInviteNotPendingException>(),
      1335: isA<AuthorInviteRequestNotOpenException>(),
    };
    for (final e in cases.entries) {
      test('accept ${e.key}', () async {
        await withRemoteWire(
          const {},
          <WireSent>[],
          (remote) => expectLater(
            AuthorInviteRepository(remote).accept(inviteId: _inviteId),
            throwsA(e.value),
          ),
          errors: {'AuthorInviteAccept': wireCodeError(e.key)},
        );
      });
    }

    test('beaconInvites maps typed errors too', () async {
      await withRemoteWire(
        const {},
        <WireSent>[],
        (remote) => expectLater(
          AuthorInviteRepository(remote).beaconInvites(beaconId: _beaconId),
          throwsA(isA<AuthorInviteNotFoundException>()),
        ),
        errors: {'BeaconAuthorInvites': wireCodeError(1333)},
      );
    });
  });
}
