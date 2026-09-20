@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_event.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy outbox PG test';

  group('BeaconHierarchyOutboxRepository — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyOutboxRepository outbox;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      outbox = BeaconHierarchyOutboxRepository(session.db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_deliveries WHERE event_id LIKE 'HE%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_hierarchy_events WHERE id LIKE 'HE%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE hierarchy_notice_identity LIKE 'hierarchy:%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    test('delivery table has five states and lease columns', () async {
      final states = await writer.execute(r'''
SELECT pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.beacon_hierarchy_deliveries'::regclass
  AND conname = 'beacon_hierarchy_deliveries_state_check'
''');
      expect(states.single.first, contains("'parked'"));
      expect(states.single.first, contains("'suppressed'"));

      final columns = await writer.execute(r'''
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon_hierarchy_deliveries'
  AND column_name IN ('lease_owner', 'lease_until', 'state')
ORDER BY column_name
''');
      expect(columns.map((r) => r[0]), ['lease_owner', 'lease_until', 'state']);
      expect(columns.firstWhere((r) => r[0] == 'lease_owner')[2], 'YES');
      expect(columns.firstWhere((r) => r[0] == 'lease_until')[2], 'YES');
    }, skip: skipReason);

    test('room message author nullable with system discriminator constraint', () async {
      await fixture.seedFullTopology();

      final authorColumn = await writer.execute(r'''
SELECT is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon_room_message'
  AND column_name = 'author_id'
''');
      expect(authorColumn.single.first, 'YES');

      final fk = await writer.execute(r'''
SELECT pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.beacon_room_message'::regclass
  AND conname = 'beacon_room_message_author_id_fkey'
''');
      expect(fk.single.first, contains('ON DELETE SET NULL'));

      await expectLater(
        writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at
) VALUES (
  'Rhierviolate1', @beacon, NULL, 'no author no kind', now()
)
'''),
          parameters: {'beacon': BeaconHierarchyTopology.beaconA},
        ),
        throwsA(isA<Exception>()),
      );

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, system_message_kind, hierarchy_notice_identity, created_at
) VALUES (
  @id, @beacon, NULL, '', @kind, @identity, now()
)
'''),
        parameters: {
          'id': 'Rhiersystem01',
          'beacon': BeaconHierarchyTopology.beaconA,
          'kind': BeaconRoomSystemMessageKind.hierarchyLifecycle,
          'identity': 'hierarchy:HEtest0001:${BeaconHierarchyTopology.beaconB}',
        },
      );
    }, skip: skipReason);

    test('records events with per-source sequence under beacon lock', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final event = await outbox.recordEvent(
        sourceBeaconId: BeaconHierarchyTopology.beaconB,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.reviewOpen,
        occurredAt: DateTime.utc(2026, 2, 1),
        actorUserId: BeaconHierarchyTopology.bobId,
      );
      expect(event.sourceSequence, 1);

      final seqRow = await writer.execute(
        Sql.named(
          'SELECT hierarchy_event_sequence FROM public.beacon WHERE id = @id',
        ),
        parameters: {'id': BeaconHierarchyTopology.beaconB},
      );
      expect(seqRow.single.first, 1);
    }, skip: skipReason);

    test('traverses descendants through deleted intermediate nodes', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await writer.execute(
        Sql.named(
          'UPDATE public.beacon SET status = 2 WHERE id = @id',
        ),
        parameters: {'id': BeaconHierarchyTopology.beaconB},
      );

      final event = await outbox.recordEvent(
        sourceBeaconId: BeaconHierarchyTopology.beaconB,
        fromStatus: BeaconStatus.deleted,
        toStatus: BeaconStatus.deleted,
        occurredAt: DateTime.utc(2026, 2, 2),
      );
      final targets = await outbox.collectPublishedTopologyTargets(
        sourceBeaconId: BeaconHierarchyTopology.beaconB,
        eventId: event.eventId,
      );
      expect(
        targets.map((t) => t.targetBeaconId),
        contains(BeaconHierarchyTopology.beaconC),
      );
      expect(
        targets.map((t) => t.targetBeaconId),
        contains(BeaconHierarchyTopology.beaconA),
      );
    }, skip: skipReason);

    test('claims due deliveries with lease fencing', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      final event = await outbox.recordEvent(
        sourceBeaconId: BeaconHierarchyTopology.beaconA,
        fromStatus: BeaconStatus.open,
        toStatus: BeaconStatus.closed,
        occurredAt: DateTime.utc(2026, 2, 3),
      );
      await outbox.insertDeliveryTargets(
        event: event,
        targets: [
          BeaconHierarchyDeliveryTarget(
            eventId: event.eventId,
            targetBeaconId: BeaconHierarchyTopology.beaconB,
            direction: BeaconHierarchyDeliveryDirection.ancestor,
          ),
        ],
      );

      final claimed = await outbox.claimDueDeliveries(
        leaseOwner: 'worker-1',
        now: DateTime.timestamp(),
        limit: 5,
      );
      expect(claimed, hasLength(1));

      await outbox.markDeliveryDelivered(
        eventId: event.eventId,
        targetBeaconId: BeaconHierarchyTopology.beaconB,
        leaseOwner: 'worker-1',
      );

      final staleUpdate = await writer.execute(
        Sql.named(r'''
UPDATE public.beacon_hierarchy_deliveries
SET state = 'pending'
WHERE event_id = @eventId AND target_beacon_id = @target
  AND state = 'leased' AND lease_owner = @owner
'''),
        parameters: {
          'eventId': event.eventId,
          'target': BeaconHierarchyTopology.beaconB,
          'owner': 'worker-stale',
        },
      );
      expect(staleUpdate.affectedRows, 0);

      final terminal = await writer.execute(
        Sql.named(
          'SELECT state FROM public.beacon_hierarchy_deliveries WHERE event_id = @eventId',
        ),
        parameters: {'eventId': event.eventId},
      );
      expect(terminal.single.first, BeaconHierarchyDeliveryStateWire.delivered);
    }, skip: skipReason);

  });
}
