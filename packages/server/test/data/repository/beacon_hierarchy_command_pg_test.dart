@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura_server/data/repository/beacon_hierarchy_command_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy command PG test';

  group('BeaconHierarchyCommandRepository — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyCommandRepository commands;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      commands = BeaconHierarchyCommandRepository(session.db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_promotions WHERE child_beacon_id LIKE 'Bhiermd%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_child_commands WHERE actor_user_id LIKE 'Uhier%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id LIKE 'Bhiermd%'",
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

    test('records command outcomes and distinguishes hash conflicts', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      const commandId = 'cmd-hash-test-01';
      const childId = 'Bhiermdchild01';
      await insertPublishedChildBeacon(
        writer: writer,
        childId: childId,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.bobId,
        title: 'Command child',
      );

      await commands.recordCreateOutcome(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
        normalizedInputHash: 'hash-a',
        creationContext: const BeaconCreationContextChild(
          parentBeaconId: BeaconHierarchyTopology.beaconA,
        ),
        outcome: BeaconChildCommandOutcome.created,
        resultBeaconId: childId,
      );

      final replay = await commands.findCommand(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
      );
      expect(replay?.normalizedInputHash, 'hash-a');
      expect(replay?.outcome, BeaconChildCommandOutcome.created);

      await commands.recordCreateOutcome(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
        normalizedInputHash: 'hash-b',
        creationContext: const BeaconCreationContextChild(
          parentBeaconId: BeaconHierarchyTopology.beaconA,
        ),
        outcome: BeaconChildCommandOutcome.replayed,
        resultBeaconId: childId,
      );

      final conflict = await commands.findCommand(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
      );
      expect(conflict?.normalizedInputHash, 'hash-a');
      expect(conflict?.outcome, BeaconChildCommandOutcome.created);
    }, skip: skipReason);

    test('enforces concurrent unique promotion per source message', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      const child1 = 'Bhiermdchild02';
      const child2 = 'Bhiermdchild03';
      await insertPublishedChildBeacon(
        writer: writer,
        childId: child1,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.bobId,
        title: 'Promoted child 1',
      );
      await insertPublishedChildBeacon(
        writer: writer,
        childId: child2,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.carolId,
        title: 'Promoted child 2',
      );

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_promotions (
  child_beacon_id, parent_beacon_id, source_message_id, promoter_user_id, published_at
) VALUES (@child, @parent, @source, @promoter, now())
'''),
        parameters: {
          'child': child1,
          'parent': BeaconHierarchyTopology.beaconA,
          'source': BeaconHierarchyTopology.generalMessageOnA,
          'promoter': BeaconHierarchyTopology.bobId,
        },
      );

      await expectLater(
        writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_promotions (
  child_beacon_id, parent_beacon_id, source_message_id, promoter_user_id, published_at
) VALUES (@child, @parent, @source, @promoter, now())
'''),
          parameters: {
            'child': child2,
            'parent': BeaconHierarchyTopology.beaconA,
            'source': BeaconHierarchyTopology.generalMessageOnA,
            'promoter': BeaconHierarchyTopology.carolId,
          },
        ),
        throwsA(isA<Exception>()),
      );

      final winner = await commands.findPublishedChildForSourceMessage(
        sourceMessageId: BeaconHierarchyTopology.generalMessageOnA,
      );
      expect(winner, child1);
    }, skip: skipReason);

    test('markCommandDeleted preserves command-gone marker', () async {
      await fixture.seedFullTopology();
      const commandId = 'cmd-gone-01';
      await commands.recordCreateOutcome(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
        normalizedInputHash: 'gone-hash',
        creationContext: const BeaconCreationContextChild(
          parentBeaconId: BeaconHierarchyTopology.beaconA,
        ),
        outcome: BeaconChildCommandOutcome.created,
        resultBeaconId: null,
      );
      await commands.markCommandDeleted(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
      );
      final gone = await commands.findCommand(
        actorUserId: BeaconHierarchyTopology.bobId,
        clientCommandId: commandId,
      );
      expect(gone?.deleted, isTrue);
      expect(gone?.resultBeaconId, isNull);
      expect(gone?.normalizedInputHash, 'gone-hash');
    }, skip: skipReason);
  });
}
