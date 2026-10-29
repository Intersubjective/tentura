@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';

import '../../client/test/support/field_remote_hint_contract.dart';
import '../../client/test/support/person_untrust_mutation_contract.dart';
import 'support/disposable_pg_target.dart';
import 'support/profile_trust_graph_pg_fixture.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REMOTE_FIELD_HINT_DELIVERY_TEST_DB',
    defaultNamePrefix: 'tentura_test_remote_field_delivery',
  );
  final reachable = await canReachPostgresAdmin(target);
  test(
    'published Requests and remote untrust reach the viewer socket',
    () async {
      const viewerId = ProfileTrustGraphPgFixture.alice;
      const contactId = ProfileTrustGraphPgFixture.bob;
      expect(viewerId, remoteHintViewerId);
      expect(contactId, remoteHintContactId);
      final server = ProfileTrustGraphPgFixture(target);
      await server.open();
      try {
        await server.seedPublishedMutualTrust();
        final requests = BeaconRepository(server.db);
        final first = await requests.createBeacon(
          authorId: contactId,
          title: 'Published while Kai keeps Field open',
          description: 'Discoverable without sending to anyone',
          isDiscoverable: true,
        );
        await server.flushNotifications();
        expect(
          server.notificationsReceived.where(
            (hint) => switch (hint) {
              {
                'entity': 'constellation_item',
                'id': final String id,
                'user_ids': final List<Object?> recipients,
              } =>
                id == first.id && recipients.contains(viewerId),
              _ => false,
            },
          ),
          isNotEmpty,
          reason: 'a mutual-contact viewer is a publication hint recipient',
        );
        expect(
          _frames(server, 'constellation_item', id: first.id),
          contains(equals(remoteRequestFrame(first.id))),
        );

        expect(
          await server.executeMutation(
            personUntrustMutationRequest(viewerId),
            actorId: contactId,
          ),
          {'__typename': 'Mutation', 'userVote': 0},
        );
        await server.flushNotifications();
        expect(await server.voteAmount(contactId, viewerId), 0);
        expect(
          server.notificationsReceived.where(
            (hint) => switch (hint) {
              {
                'entity': 'relationship',
                'actor_user_id': contactId,
                'user_ids': final List<Object?> recipients,
              } =>
                recipients.contains(viewerId) && recipients.contains(contactId),
              _ => false,
            },
          ),
          isNotEmpty,
          reason: 'both endpoints receive the committed untrust hint',
        );
        expect(
          _frames(server, 'relationship').any(
            (frame) => switch (frame['payload']) {
              {'id': viewerId, 'actor_user_id': contactId} => true,
              _ => false,
            },
          ),
          isTrue,
          reason: 'exercise the actual viewer-named, contact-actor envelope',
        );

        final untrustFrames = _frames(server, 'relationship').where((frame) {
          return switch (frame['payload']) {
            {'id': viewerId, 'actor_user_id': contactId} => true,
            _ => false,
          };
        });
        expect(untrustFrames, isNotEmpty);
        for (final frame in untrustFrames) {
          if (frame['payload'] case {'event': final String operation}) {
            expect(operation, isIn(['insert', 'update', 'delete']));
            expect(frame, remoteUntrustFrame(operation));
          } else {
            fail('Relationship hint must carry an operation');
          }
        }

        final second = await requests.createBeacon(
          authorId: contactId,
          title: 'Published while Kai uses another tab',
          description: 'Still discoverable to the viewer who trusts Max',
          isDiscoverable: true,
        );
        await server.flushNotifications();
        expect(
          _frames(server, 'constellation_item', id: second.id),
          contains(equals(remoteRequestFrame(second.id))),
        );
      } finally {
        await server.close();
      }
    },
    skip: reachable ? false : 'Postgres admin database is unavailable',
  );
}

List<Map<String, dynamic>> _frames(
  ProfileTrustGraphPgFixture server,
  String kind, {
  String? id,
}) => [
  for (final raw in server.viewerFrames)
    if (jsonDecode(raw) case final Map<String, dynamic> frame)
      if (frame case {
        'path': 'entity_changes',
        'payload': final Map<String, dynamic> payload,
      })
        if (payload['entity'] == kind && (id == null || payload['id'] == id))
          frame,
];
