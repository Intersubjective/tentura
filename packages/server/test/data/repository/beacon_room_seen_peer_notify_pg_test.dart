@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon_room_seen peer NOTIFY PG test';

  group('beacon_room_seen room_seen_peer NOTIFY — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late Connection listener;
    late BeaconHierarchyFixture fixture;
    late BeaconRoomRepository room;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      room = BeaconRoomRepository(session.db);
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      notifications.clear();
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await notificationSubscription.cancel();
      await listener.close();
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

    List<Map<String, dynamic>> peerNotifications({String? beaconId}) =>
        notifications.where((message) {
          if (message['entity'] != 'room_seen_peer') return false;
          if (beaconId != null && message['id'] != beaconId) return false;
          return true;
        }).toList();

    Future<Map<String, dynamic>> waitForPeerNotify(String beaconId) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        final matches = peerNotifications(beaconId: beaconId);
        if (matches.isNotEmpty) {
          return matches.last;
        }
        await settle();
      }
      fail('Timed out waiting for room_seen_peer NOTIFY on $beaconId');
    }

    Future<void> waitForNoPeerNotify(String beaconId) async {
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(peerNotifications(beaconId: beaconId), isEmpty);
    }

    Future<void> seedTree() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
    }

    Future<void> seedPeerRecipientFixture() async {
      final beaconId = BeaconHierarchyTopology.beaconB;
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES
  ('Pseenpeer001', @beaconId, @aliceId, 0, 0, @admitted, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pseenpeer002', @beaconId, @frankId, 0, 0, @admitted, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pseenpeer003', @beaconId, @carolId, 1, 0, @none, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Pseenpeer004', @beaconId, @daveId, 0, 0, @none, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
        parameters: {
          'beaconId': beaconId,
          'aliceId': BeaconHierarchyTopology.aliceId,
          'frankId': BeaconHierarchyTopology.frankId,
          'carolId': BeaconHierarchyTopology.carolId,
          'daveId': BeaconHierarchyTopology.daveId,
          'admitted': RoomAccessBits.admitted,
          'none': RoomAccessBits.none,
        },
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beaconId, @carolId)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'beaconId': beaconId,
          'carolId': BeaconHierarchyTopology.carolId,
        },
      );
    }

    Future<void> insertGeneralSeen({
      required String userId,
      required String beaconId,
      required DateTime at,
    }) => writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES (@userId, @beaconId, NULL, @at)
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)
'''),
      parameters: {
        'userId': userId,
        'beaconId': beaconId,
        'at': at,
      },
    );

    test(
      'INSERT of General beacon_room_seen emits room_seen_peer update with payload keys',
      () async {
        await seedTree();
        notifications.clear();
        const beaconId = BeaconHierarchyTopology.beaconB;
        const seenUser = BeaconHierarchyTopology.eveId;
        final seenAt = DateTime.utc(2026, 6, 15, 12);

        await insertGeneralSeen(
          userId: seenUser,
          beaconId: beaconId,
          at: seenAt,
        );

        final notify = await waitForPeerNotify(beaconId);
        expect(notify['event'], 'update');
        expect(notify['entity'], 'room_seen_peer');
        expect(notify['id'], beaconId);
        expect(notify.containsKey('seen_user_id'), isTrue);
        expect(notify.containsKey('last_seen_at'), isTrue);
        expect(notify['seen_user_id'], seenUser);
        expect(
          DateTime.parse(notify['last_seen_at'] as String).toUtc(),
          seenAt,
        );
        expect(peerNotifications(beaconId: beaconId), hasLength(1));
      },
      skip: skipReason,
    );

    test(
      'UPDATE advancing last_seen_at emits room_seen_peer NOTIFY',
      () async {
        await seedTree();
        const beaconId = BeaconHierarchyTopology.beaconB;
        const seenUser = BeaconHierarchyTopology.eveId;
        final initial = DateTime.utc(2026, 6, 16, 10);
        final advanced = DateTime.utc(2026, 6, 16, 11);

        await room.markBeaconRoomSeen(
          userId: seenUser,
          beaconId: beaconId,
          threadItemId: null,
          at: initial,
        );
        await waitForPeerNotify(beaconId);
        notifications.clear();

        await room.markBeaconRoomSeen(
          userId: seenUser,
          beaconId: beaconId,
          threadItemId: null,
          at: advanced,
        );

        final notify = await waitForPeerNotify(beaconId);
        expect(notify['event'], 'update');
        expect(notify['seen_user_id'], seenUser);
        expect(
          DateTime.parse(notify['last_seen_at'] as String).toUtc(),
          advanced,
        );
      },
      skip: skipReason,
    );

    test(
      'stale upsert that GREATEST keeps unchanged emits no room_seen_peer NOTIFY',
      () async {
        await seedTree();
        const beaconId = BeaconHierarchyTopology.beaconB;
        const seenUser = BeaconHierarchyTopology.eveId;
        final newer = DateTime.utc(2026, 6, 17, 12);
        final stale = DateTime.utc(2026, 6, 17, 9);

        await room.markBeaconRoomSeen(
          userId: seenUser,
          beaconId: beaconId,
          threadItemId: null,
          at: newer,
        );
        await waitForPeerNotify(beaconId);
        notifications.clear();

        await room.markBeaconRoomSeen(
          userId: seenUser,
          beaconId: beaconId,
          threadItemId: null,
          at: stale,
        );
        await waitForNoPeerNotify(beaconId);
      },
      skip: skipReason,
    );

    test(
      'thread-item seen row emits no room_seen_peer NOTIFY',
      () async {
        await seedTree();
        const beaconId = BeaconHierarchyTopology.beaconB;
        const threadItemId = 'CIseenpeer01';
        const seenUser = BeaconHierarchyTopology.eveId;
        final seenAt = DateTime.utc(2026, 6, 18, 12);

        await writer.execute(
          "SET tentura.discussion_internal_fixture = 'allow_non_general'",
        );
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, 'Peer notify thread fixture', '', @creatorId,
  true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
  @source, 0
)
ON CONFLICT (id) DO NOTHING
'''),
          parameters: {
            'id': threadItemId,
            'beaconId': beaconId,
            'kind': coordinationItemKindAsk,
            'status': coordinationItemStatusOpen,
            'creatorId': BeaconHierarchyTopology.bobId,
            'source': coordinationItemSourceDefault,
          },
        );

        notifications.clear();
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES (@userId, @beaconId, @threadItemId, @at)
ON CONFLICT (user_id, beacon_id, thread_item_id) WHERE thread_item_id IS NOT NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)
'''),
          parameters: {
            'userId': seenUser,
            'beaconId': beaconId,
            'threadItemId': threadItemId,
            'at': seenAt,
          },
        );
        await waitForNoPeerNotify(beaconId);

        notifications.clear();
        await insertGeneralSeen(
          userId: seenUser,
          beaconId: beaconId,
          at: seenAt.add(const Duration(hours: 1)),
        );
        await waitForPeerNotify(beaconId);
      },
      skip: skipReason,
    );

    test(
      'room_seen_peer recipients are author, admitted participants, and stewards',
      () async {
        await seedTree();
        await seedPeerRecipientFixture();
        const beaconId = BeaconHierarchyTopology.beaconB;
        const seenUser = BeaconHierarchyTopology.eveId;
        final seenAt = DateTime.utc(2026, 6, 19, 12);

        notifications.clear();
        await insertGeneralSeen(
          userId: seenUser,
          beaconId: beaconId,
          at: seenAt,
        );

        final notify = await waitForPeerNotify(beaconId);
        final recipients = (notify['user_ids']! as List).cast<String>().toSet();
        final expected = {
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyTopology.aliceId,
          BeaconHierarchyTopology.frankId,
          BeaconHierarchyTopology.carolId,
        };
        expect(recipients, expected);
        expect(recipients, isNot(contains(BeaconHierarchyTopology.daveId)));
      },
      skip: skipReason,
    );
  }, skip: skipReason);
}
