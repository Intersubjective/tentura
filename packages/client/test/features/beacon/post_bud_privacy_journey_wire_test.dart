@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../domain/attention/attention_case_test_support.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';

const _anna = 'Ubudjourney0A';
const _bob = 'Ubudjourney0B';
const _carol = 'Ubudjourney0C';
const _kira = 'Ubudjourney0K';
const _dina = 'Ubudjourney0D';
const _eli = 'Ubudjourney0E';
const _postBody = 'Plans for the neighborhood garden';

void main() {
  test(
    'a private Post bud grants only the selected members access and keeps the '
    'Request out of everyone else’s Post, attention feeds and digest',
    () async {
      final server = await ProductionReceiptTransport.start(
        serverFixture: 'test/support/post_bud_journey_transport.dart',
      );
      addTearDown(server.close);
      final failures = <String>[];

      void check(String label, Object? actual, Object? wanted) {
        try {
          expect(actual, wanted, reason: label);
        } on TestFailure catch (failure) {
          failures.add(failure.toString().trim());
        }
      }

      final private = await _as(
        server,
        _anna,
        (session) => session.bud('private'),
      );
      final discoverable = await _as(
        server,
        _anna,
        (session) => session.bud('public', discoverable: true),
      );
      final closed = await _as(
        server,
        _anna,
        (session) => session.bud('close', closePost: true),
      );

      await _as(server, _carol, (session) async {
        check(
          'Carol reads the private Request',
          await session.content(private.id),
          (private.title, private.description),
        );
        check(
          'Carol receives the invitation when the Post closes',
          (await session.invites.myPending()).map((item) => item.beaconId),
          contains(closed.id),
        );
        check(
          'Carol reads the continuation',
          await session.content(closed.id),
          (closed.title, closed.description),
        );
      });

      await _as(server, _dina, (session) async {
        final ordinary = await session.content('Bbudj-control');
        expect(ordinary, ('Fix the greenhouse door', 'Bring a screwdriver.'));
        expect(
          await session.content(discoverable.post),
          isNull,
          reason: 'Dina is not a Post member',
        );
        check(
          'A trust-visible peer can read the discoverable bud',
          await session.content(discoverable.id),
          (discoverable.title, discoverable.description),
        );
      });

      final ownerRequests = <String, Beacon>{};
      await _as(server, _anna, (session) async {
        for (final bud in [private, closed]) {
          final label = 'Anna after ${bud.kind} bud';
          final request = await session.beacons.fetchBeaconById(bud.id);
          ownerRequests[bud.id] = request;
          check(
            '$label reads her Request',
            (request.title, request.description),
            (bud.title, bud.description),
          );
          check(
            '$label sees Carol in her invite list',
            (await session.invites.beaconInvites(
              beaconId: bud.id,
            )).map((invite) => invite.inviteeId),
            [_carol],
          );
          check(
            '$label sees the Request on her Post',
            await session.childIds(bud.post),
            contains(bud.id),
          );
          final room = await session.room.fetchMessages(beaconId: bud.post);
          check(
            '$label sees the Request notice and its title in her Post room',
            [
              for (final message in room)
                if (message.hierarchyPayload
                    case RoomMessageHierarchyChildCreated(
                      :final childBeaconId,
                      :final title,
                    ))
                  (childBeaconId, title),
            ],
            contains((bud.id, bud.title)),
          );
        }
        check(
          'Close and continue closes the Post',
          (await session.beacons.fetchBeaconById(closed.post)).status,
          BeaconStatus.closed,
        );
        final history = await session.feed(AttentionFeedDestinationId.history);
        final forYou = await session.feed(
          AttentionFeedDestinationId.activityStream,
        );
        check(
          'Anna sees activity from budding the private Request',
          [...history, ...forYou].any((item) => _refersTo(item, private)),
          isTrue,
        );
      });

      for (final (viewer, name) in [(_bob, 'Bob'), (_kira, 'Kira')]) {
        await _as(server, viewer, (session) async {
          final history = await session.feed(
            AttentionFeedDestinationId.history,
          );
          final forYou = await session.feed(
            AttentionFeedDestinationId.activityStream,
          );
          for (final bud in [private, closed]) {
            final label = '$name after ${bud.kind} bud';
            final ownPost = await session.beacons.fetchBeaconById(bud.post);
            check(
              '$label cannot open the Request',
              await session.content(bud.id),
              isNull,
            );
            check(
              '$label sees no Request in the Post child list',
              await session.childIds(bud.post),
              isNot(contains(bud.id)),
            );
            final room = await session.room.fetchMessages(beaconId: bud.post);
            final source = room.singleWhere(
              (message) => message.id == bud.root,
            );
            expect(
              source.body,
              _postBody,
              reason: '$label still sees the source',
            );
            check(
              '$label sees no Request marker on the source',
              source.promotedChildBeaconId,
              isNull,
            );
            check(
              '$label sees no bud notice or continuation reference',
              [
                for (final message in room)
                  if (message.systemMessageKind ==
                          BeaconRoomSystemMessageKind.childCreated ||
                      message.body.contains(bud.title) ||
                      (message.systemPayloadJson ?? '').contains(bud.id) ||
                      (message.systemPayloadJson ?? '').contains(bud.title))
                    message.id,
              ],
              isEmpty,
            );
            for (final (feed, items) in [
              ('For You', forYou),
              ('History', history),
            ]) {
              check(
                '$label has no corresponding $feed entry',
                items.where(
                  (item) =>
                      _refersTo(item, bud) ||
                      (bud == closed && item.beaconId == bud.post),
                ),
                isEmpty,
              );
            }
            final involvement = await server.graphql(
              viewer,
              {'id': bud.id},
              path: '/stored-involvement',
            );
            expect(involvement.statusCode, 200);
            check(
              '$label has no involvement stored in Postgres',
              jsonDecode(involvement.body),
              isFalse,
            );
            check(
              '$label receives involvement for the Post only',
              (await session.forward.fetchInvolvementForBeacons([
                ownPost,
                ownerRequests[bud.id]!,
              ])).keys,
              [bud.post],
            );
          }
        });
      }

      // Observe the bud's own delivery before subsequent help offers can
      // produce unrelated attention entries and digest lines for its author.
      final response = await server.graphql(_anna, {}, path: '/digests');
      expect(response.statusCode, 200);
      final digests = jsonDecode(response.body) as Map<String, dynamic>;
      String digest(String id) => (digests[id] as List? ?? []).join('\n');
      check(
        'Anna receives a digest line for the private Request',
        digest(_anna),
        allOf(contains(private.id), contains(private.title)),
      );
      expect(
        digest(_carol),
        allOf(contains(private.id), contains(private.title)),
        reason: 'the digest worker delivers the selected recipient’s line',
      );
      for (final (viewer, name) in [(_bob, 'Bob'), (_kira, 'Kira')]) {
        check(
          '$name gets no private Request or close-and-continue digest line',
          digest(viewer),
          allOf([
            for (final text in [
              private.id,
              private.title,
              closed.id,
              closed.title,
              closed.post,
            ])
              isNot(contains(text)),
          ]),
        );
      }

      await _as(
        server,
        _carol,
        (session) =>
            _forwardAndOffer(session, server, _carol, private.id, check),
      );
      await _as(server, _dina, (session) async {
        await _forwardAndOffer(session, server, _dina, 'Bbudj-control', check);
        await _forwardAndOffer(session, server, _dina, discoverable.id, check);
      });

      if (failures.isNotEmpty) fail(failures.join('\n\n'));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

bool _refersTo(AttentionReceipt item, _Bud bud) =>
    item.beaconId == bud.id ||
    item.targetEntityId == bud.id ||
    [
      item.actionUrl,
      item.presentationPayloadJson,
      item.title,
      item.body,
      item.beaconTitle,
      item.relatedBeaconTitle,
    ].whereType<String>().any(
      (text) => text.contains(bud.id) || text.contains(bud.title),
    ) ||
    item.eventsPreview.any((event) => _refersTo(event, bud));

Future<void> _forwardAndOffer(
  _Session session,
  ProductionReceiptTransport server,
  String viewer,
  String id,
  void Function(String, Object?, Object?) check,
) async {
  const message = 'I can bring tools on Saturday.';
  final forward = await session.forward.forwardBeacon(
    beaconId: id,
    recipientIds: [_eli],
  );
  check('$viewer forwards $id', forward.deliveredRecipientIds, [_eli]);
  check(
    '$viewer offers help on $id',
    await session.forward.offerHelp(beaconId: id, message: message),
    isTrue,
  );
  final response = await server.graphql(
    viewer,
    {'id': id, 'recipient': _eli, 'message': message},
    path: '/stored-actions',
  );
  expect(response.statusCode, 200);
  check(
    'Postgres stores $viewer’s forward and help offer on $id',
    jsonDecode(response.body),
    [true, true],
  );
}

Future<T> _as<T>(
  ProductionReceiptTransport server,
  String viewer,
  Future<T> Function(_Session) action,
) => http.runWithClient(
  () async {
    final session = _Session(viewer);
    try {
      await session.remote.setSessionAuth();
      return await action(session);
    } finally {
      await session.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': viewer,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return server.graphql(
      viewer,
      jsonDecode(request.body) as Map<String, dynamic>,
      path: request.url.path.endsWith('/v1/graphql') ? '/hasura' : '/graphql',
    );
  }),
);

final class _Bud {
  const _Bud(this.kind, this.id);

  final String kind;
  final String id;
  String get post => 'Bbudj-${kind.padRight(7, '0')}';
  String get root => 'Rbudj-${kind.padRight(7, '0')}';
  String get title => 'Move the greenhouse ($kind)';
  String get description => 'Two people to move the frame.';
}

final class _Session {
  _Session(this.viewer);

  final String viewer;
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  final sync = buildTestRealtimeSync();
  late final beacons = BeaconRepository(remote, sync.port);
  late final forward = ForwardRepository(remote, beacons, sync.port);
  late final room = BeaconThreadsRepository(remote, sync.port);
  late final invites = AuthorInviteRepository(remote);

  Future<_Bud> bud(
    String kind, {
    bool discoverable = false,
    bool closePost = false,
  }) async {
    final draft = _Bud(kind, '');
    final result = await PostBudRepository(remote).budFromPost(
      postId: draft.post,
      sourceMessageId: draft.root,
      clientCommandId: 'neighborhood-garden-$kind',
      title: draft.title,
      description: draft.description,
      isDiscoverable: discoverable,
      invitees: const [PostBudInvitee(userId: _carol)],
      closePost: closePost,
    );
    expect(result.outcome, PostBudOutcome.created);
    expect(result.childBeaconId, isNotEmpty);
    expect(
      result.invitees.map((entry) => (entry.userId, entry.outcome)),
      [(_carol, PostBudInviteOutcome.invited)],
    );
    return _Bud(kind, result.childBeaconId!);
  }

  Future<(String, String)?> content(String id) async {
    try {
      final beacon = await beacons.fetchBeaconById(id);
      return (beacon.title, beacon.description);
    } on BeaconFetchException {
      return null;
    }
  }

  Future<Iterable<String>> childIds(String post) async {
    final hierarchy = BeaconHierarchyRepository(remote);
    return [
      for (final group in BeaconHierarchyChildGroup.values)
        ...(await hierarchy.fetchChildren(
          parentBeaconId: post,
          group: group,
        )).summaries.map((child) => child.beaconId),
    ];
  }

  Future<List<AttentionReceipt>> feed(String destination) async {
    final accounts = AttentionCaseTestAccounts();
    final attention = AttentionCase(
      AttentionRepository(remote),
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('PostBudJourneyAttention'),
    );
    accounts.emit(viewer);
    await Future<void>.delayed(Duration.zero);
    final cubit = UpdatesFeedCubit(
      destinationId: destination,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('PostBudJourneyFeed'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    try {
      if (!cubit.state.firstLoadDone) {
        await cubit.stream
            .firstWhere((state) => state.firstLoadDone || state.hasRefreshError)
            .timeout(const Duration(seconds: 15));
      }
      expect(
        cubit.state.hasRefreshError,
        isFalse,
        reason: '$viewer $destination',
      );
      expect(
        cubit.state.hasNextPage,
        isFalse,
        reason: 'the fixture fits one page',
      );
      return cubit.state.items;
    } finally {
      await cubit.close();
      await attention.dispose();
      await accounts.dispose();
    }
  }

  Future<void> close() async {
    await forward.dispose();
    await room.dispose();
    await beacons.dispose();
    await sync.port.dispose();
    await remote.close();
  }
}
