@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/disposable_pg_target.dart';
import 'support/profile_trust_graph_pg_fixture.dart';

const _alice = ProfileTrustGraphPgFixture.alice;
const _bob = ProfileTrustGraphPgFixture.bob;

Future<void> main() async {
  final target = ProfileTrustGraphPgFixture.newTarget();
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';
  late ProfileTrustGraphPgFixture fixture;

  Future<void> profileUntrust(String actor, String person) async {
    // This is also checked against the actual serialized request from
    // ProfileViewCase.removeFriend in the Flutter/Postgres integration cases.
    final document = File(
      '../client/lib/features/like/data/gql/like_user_by_id.graphql',
    ).readAsStringSync();
    expect(
      await fixture.executeMutation(
        {
          'query': document,
          'operationName': 'UserVote',
          'variables': {'objectId': person, 'amount': 0},
        },
        actorId: actor,
      ),
      {'userVote': 0},
    );
    expect(
      await fixture.voteAmount(actor, person),
      0,
      reason: 'the profile-path untrust was committed',
    );
  }

  if (reachable) {
    setUpAll(() async {
      fixture = ProfileTrustGraphPgFixture(target);
      await fixture.open();
    });
    setUp(() => fixture.seedPublishedMutualTrust());
    tearDownAll(() => fixture.close());
  }

  group(
    'Trust graph reads committed profile trust changes',
    () {
      test('profile untrust removes only the viewer outgoing edge before '
          'publication acknowledgment', () async {
        await profileUntrust(_alice, _bob);
        expect(await fixture.edges(), {(_bob, _alice)});
      });

      test('reopening the graph after profile untrust does not restore a '
          'mutual edge from published state', () async {
        await profileUntrust(_alice, _bob);
        final reloadedConnection = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          final rows = await reloadedConnection.execute(
            ProfileTrustGraphPgFixture.edgeQuery,
          );
          expect(
            {for (final row in rows) (row[0]! as String, row[1]! as String)},
            {(_bob, _alice)},
          );
        } finally {
          await reloadedConnection.close();
        }
      });

      test('remote profile untrust notifies the viewer websocket and removes '
          'the incoming edge before publication acknowledgment', () async {
        await profileUntrust(_bob, _alice);
        await fixture.flushNotifications();
        final hints = fixture.notificationsReceived.where(
          (message) => message['entity'] == 'relationship',
        );
        expect(hints, isNotEmpty);
        expect(
          hints.any(
            (message) =>
                message['actor_user_id'] == _bob &&
                (message['user_ids']! as List).contains(_alice),
          ),
          isTrue,
        );
        final frames = fixture.viewerFrames
            .map((frame) => jsonDecode(frame) as Map<String, dynamic>)
            .where(
              (frame) =>
                  frame['path'] == 'entity_changes' &&
                  (frame['payload'] as Map)['entity'] == 'relationship',
            );
        expect(
          frames,
          isNotEmpty,
          reason: 'untrust must traverse LISTEN and real websocket fan-out',
        );
        expect(
          frames.any(
            (frame) => (frame['payload'] as Map)['actor_user_id'] == _bob,
          ),
          isTrue,
        );
        expect(await fixture.edges(), {(_alice, _bob)});
      });
    },
    skip: skipReason,
  );
}
