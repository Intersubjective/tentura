@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';
import 'beacon_hierarchy_visibility_pg_support.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy realtime PG test';

  group('beacon_hierarchy realtime producers — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late Connection listener;
    late BeaconHierarchyFixture fixture;
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

    Future<List<Map<String, dynamic>>> waitForKind(
      String kind, {
      String? aggregateId,
      int minCount = 1,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        final matches = notifications.where((message) {
          if (message['entity'] != kind) return false;
          if (aggregateId != null && message['id'] != aggregateId) return false;
          return true;
        }).toList();
        if (matches.length >= minCount) return matches;
        await settle();
      }
      fail('Timed out waiting for $kind notifications');
    }

    Future<void> seedTree() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
    }

    test('child publication notifies parent hierarchy recipients with actor echo',
        () async {
      await seedTree();
      const actor = BeaconHierarchyTopology.aliceId;
      const childId = 'BhierRtChild01';
      await writer.execute('BEGIN');
      await writer.execute(
        Sql.named(
          r"SELECT set_config('tentura.mutating_user_id', @actor, true)",
        ),
        parameters: {'actor': actor},
      );
      await insertPublishedChildBeacon(
        writer: writer,
        childId: childId,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.bobId,
        title: 'Secret child title',
        publishedAt: DateTime.utc(2026, 2, 1),
      );
      await writer.execute('COMMIT');

      final changes = await waitForKind(
        'beacon_hierarchy',
        aggregateId: BeaconHierarchyTopology.beaconA,
      );
      expect(changes, isNotEmpty);
      for (final payload in changes) {
        expect(payload['event'], anyOf('insert', 'update'));
        expect(payload['id'], BeaconHierarchyTopology.beaconA);
        expect(payload.containsKey('title'), isFalse);
        expect(payload.containsKey('message'), isFalse);
        expect(payload['id'], isNot(childId));
      }
      expect(
        changes.any((payload) => payload['actor_user_id'] == actor),
        isTrue,
      );
      final recipients = changes
          .expand((message) => (message['user_ids']! as List).cast<String>())
          .toSet();
      expect(recipients, contains(actor));
      expect(recipients, contains(BeaconHierarchyTopology.aliceId));
    });

    test('draft child save emits no beacon_hierarchy hint', () async {
      await seedTree();
      notifications.clear();
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, parent_beacon_id, created_at, updated_at
) VALUES (
  @id, @ownerId, 'Draft secret', '', @status, @parentId,
  '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z'
)
'''),
        parameters: {
          'id': 'BhierRtDraft01',
          'ownerId': BeaconHierarchyTopology.bobId,
          'status': BeaconStatus.draft.smallintValue,
          'parentId': BeaconHierarchyTopology.beaconA,
        },
      );
      await settle();
      expect(
        notifications.where((m) => m['entity'] == 'beacon_hierarchy'),
        isEmpty,
      );
    });

    test('published child title change notifies parent without leaking title',
        () async {
      await seedTree();
      notifications.clear();
      await writer.execute(
        Sql.named(r'''
UPDATE public.beacon
SET title = 'Updated secret title'
WHERE id = @childId
'''),
        parameters: {'childId': BeaconHierarchyTopology.beaconB},
      );
      final changes = await waitForKind(
        'beacon_hierarchy',
        aggregateId: BeaconHierarchyTopology.beaconA,
      );
      final payload = changes.single;
      expect(payload['event'], 'update');
      expect(payload.containsKey('title'), isFalse);
      expect(jsonEncode(payload), isNot(contains('Updated secret title')));
    });

    test('participant revocation includes revoked account for cache eviction',
        () async {
      await seedTree();
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  'PhierfrankA01', @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
        parameters: {
          'beaconId': BeaconHierarchyTopology.beaconA,
          'userId': BeaconHierarchyTopology.frankId,
          'roomAccess': 3,
        },
      );
      notifications.clear();
      await writer.execute(
        Sql.named(r'''
DELETE FROM public.beacon_participant
WHERE beacon_id = @beaconId AND user_id = @userId
'''),
        parameters: {
          'beaconId': BeaconHierarchyTopology.beaconA,
          'userId': BeaconHierarchyTopology.frankId,
        },
      );
      final changes = await waitForKind(
        'beacon_hierarchy',
        aggregateId: BeaconHierarchyTopology.beaconA,
      );
      final recipients = changes
          .expand((message) => (message['user_ids']! as List).cast<String>())
          .toSet();
      expect(recipients, contains(BeaconHierarchyTopology.frankId));
    });

    test('parent delete notifies child parent-reference projection owner', () async {
      await seedTree();
      notifications.clear();
      await writer.execute(
        Sql.named(r'''
UPDATE public.beacon
SET status = @deleted
WHERE id = @beaconId
'''),
        parameters: {
          'beaconId': BeaconHierarchyTopology.beaconA,
          'deleted': BeaconStatus.deleted.smallintValue,
        },
      );
      final changes = await waitForKind(
        'beacon_hierarchy',
        aggregateId: BeaconHierarchyTopology.beaconB,
      );
      expect(changes.single['id'], BeaconHierarchyTopology.beaconB);
      expect(changes.single.containsKey('title'), isFalse);
    });
  }, skip: skipReason);
}
