@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy repository PG test';

  group('BeaconHierarchyRepository — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconHierarchyRepository repository;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      repository = BeaconHierarchyRepository(session.db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
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

    test('rejects immutable parent_beacon_id updates', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      await expectLater(
        writer.execute(
          Sql.named(
            'UPDATE public.beacon SET parent_beacon_id = @parent WHERE id = @id',
          ),
          parameters: {
            'parent': BeaconHierarchyTopology.beaconA,
            'id': BeaconHierarchyTopology.beaconC,
          },
        ),
        throwsA(isA<Exception>()),
      );

      await expectLater(
        writer.execute(
          Sql.named(
            'UPDATE public.beacon SET parent_beacon_id = NULL WHERE id = @id',
          ),
          parameters: {'id': BeaconHierarchyTopology.beaconB},
        ),
        throwsA(isA<Exception>()),
      );

      await expectLater(
        writer.execute(
          Sql.named(
            'UPDATE public.beacon SET parent_beacon_id = @parent WHERE id = @id',
          ),
          parameters: {
            'parent': BeaconHierarchyTopology.beaconA,
            'id': BeaconHierarchyTopology.privateDraftChildId,
          },
        ),
        throwsA(isA<Exception>()),
      );
    }, skip: skipReason);

    test('rejects self-parenting and parent cycles on insert', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      await expectLater(
        insertPublishedChildBeacon(
          writer: writer,
          childId: 'Bhiercycle001',
          parentId: 'Bhiercycle001',
          ownerId: BeaconHierarchyTopology.bobId,
          title: 'Self parent',
        ),
        throwsA(isA<Exception>()),
      );
    }, skip: skipReason);

    test('rejects missing and draft parents on insert', () async {
      await fixture.seedFullTopology();

      await expectLater(
        insertPublishedChildBeacon(
          writer: writer,
          childId: 'Bhiermiss001',
          parentId: 'Bmissing0001',
          ownerId: BeaconHierarchyTopology.bobId,
          title: 'Missing parent',
        ),
        throwsA(isA<Exception>()),
      );

      await expectLater(
        insertPublishedChildBeacon(
          writer: writer,
          childId: 'Bhiermiss002',
          parentId: BeaconHierarchyTopology.privateDraftChildId,
          ownerId: BeaconHierarchyTopology.bobId,
          title: 'Draft parent',
        ),
        throwsA(isA<Exception>()),
      );
    }, skip: skipReason);

    test('lists children with stable keyset pagination per group', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await insertPublishedChildBeacon(
        writer: writer,
        childId: 'Bhieractive01',
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Active child 1',
        publishedAt: DateTime.utc(2026, 1, 8),
      );
      await insertPublishedChildBeacon(
        writer: writer,
        childId: 'Bhieractive02',
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Active child 2',
        publishedAt: DateTime.utc(2026, 1, 7),
      );
      await insertPublishedChildBeacon(
        writer: writer,
        childId: 'Bhierfinish01',
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Finished child',
        status: BeaconStatus.closed,
        publishedAt: DateTime.utc(2026, 1, 3),
      );
      await insertPublishedChildBeacon(
        writer: writer,
        childId: 'Bhierdelete01',
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Deleted child',
        status: BeaconStatus.deleted,
        publishedAt: DateTime.utc(2026, 1, 2),
      );

      final page1 = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.active,
        first: 2,
      );
      expect(page1.summaries, hasLength(2));
      expect(page1.nextCursor, isNotNull);
      expect(
        page1.summaries.map((s) => s.beaconId),
        ['Bhieractive01', 'Bhieractive02'],
      );

      final page2 = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.active,
        first: 2,
        after: page1.nextCursor,
      );
      expect(
        page2.summaries.map((s) => s.beaconId),
        [
          BeaconHierarchyTopology.beaconB,
          BeaconHierarchyTopology.beaconD,
        ],
      );
      expect(
        page1.summaries.map((s) => s.beaconId).toSet()
            .intersection(page2.summaries.map((s) => s.beaconId).toSet()),
        isEmpty,
      );

      final finished = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.finished,
        first: 10,
      );
      expect(finished.summaries.single.beaconId, 'Bhierfinish01');

      final deleted = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.deleted,
        first: 10,
      );
      expect(deleted.summaries.single.beaconId, 'Bhierdelete01');
    }, skip: skipReason);

    test('excludes unpublished draft children from listings', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);

      final page = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.active,
        first: 20,
      );
      expect(
        page.summaries.map((s) => s.beaconId),
        isNot(contains(BeaconHierarchyTopology.privateDraftChildId)),
      );
    }, skip: skipReason);

    test('fork lineage parent does not appear as nested child listing', () async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      const forkId = 'Bhierfork0001';
      await insertPublishedChildBeacon(
        writer: writer,
        childId: forkId,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.frankId,
        title: 'Fork lineage only',
        publishedAt: DateTime.utc(2026, 1, 9),
        lineageParentBeaconId: BeaconHierarchyTopology.beaconB,
      );

      final parentId = await repository.loadImmediateParentBeaconId(forkId);
      expect(parentId, BeaconHierarchyTopology.beaconA);

      final lineageOnly = await writer.execute(
        Sql.named(
          'SELECT lineage_parent_beacon_id FROM public.beacon WHERE id = @id',
        ),
        parameters: {'id': forkId},
      );
      expect(lineageOnly.single.first, BeaconHierarchyTopology.beaconB);

      final childrenOfB = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconB,
        viewerId: BeaconHierarchyTopology.bobId,
        group: BeaconHierarchyChildGroup.active,
        first: 20,
      );
      expect(childrenOfB.summaries.map((s) => s.beaconId), [
        BeaconHierarchyTopology.beaconC,
      ]);
      expect(childrenOfB.summaries.map((s) => s.beaconId), isNot(contains(forkId)));
    }, skip: skipReason);

    test('m0154 schema exposes parent/publication columns on beacon', () async {
      final columns = await writer.execute(r'''
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon'
  AND column_name IN (
    'parent_beacon_id', 'published_at', 'hierarchy_event_sequence'
  )
ORDER BY column_name
''');
      expect(columns.map((r) => r.first), [
        'hierarchy_event_sequence',
        'parent_beacon_id',
        'published_at',
      ]);
    }, skip: skipReason);
  });
}
