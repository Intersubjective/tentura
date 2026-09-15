@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beaconChildren authorization PG test';

  group('BeaconHierarchyRepository.listChildren authorization — disposable Postgres', () {
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
      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id LIKE 'Uhier%' "
        "OR blocked_id LIKE 'Uhier%'",
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

    // seedPublishedHierarchyTree re-creates B/C/D, which drops their
    // participant rows; restore the fixture admissions afterwards.
    Future<void> seedTree() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      for (final row in <(String, String, String)>[
        ('PhierbobB01', BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.bobId),
        ('PhiercarolC01', BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.carolId),
        ('PhieraliceA01', BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.aliceId),
      ]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
'''),
          parameters: {
            'id': row.$1,
            'beaconId': row.$2,
            'userId': row.$3,
            'roomAccess': RoomAccessBits.admitted,
          },
        );
      }
    }

    Future<bool> sqlPredicate(String fn, String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.$fn(@beaconId, @viewerId)'),
        parameters: {'beaconId': beaconId, 'viewerId': viewerId},
      );
      return row.first.first! as bool;
    }

    Future<List<String>> childIds(
      String viewerId,
      BeaconHierarchyChildGroup group,
    ) async {
      final page = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: viewerId,
        group: group,
        first: 20,
      );
      return page.summaries.map((s) => s.beaconId).toList();
    }

    test('stranger who cannot read the parent gets an empty page', () async {
      await seedTree();
      // Dave owns grandchild C but has no admission, help offer or forward
      // touching A or B.
      const daveId = BeaconHierarchyTopology.daveId;
      expect(
        await sqlPredicate(
          'beacon_can_read_linked_detail',
          BeaconHierarchyTopology.beaconA,
          daveId,
        ),
        isFalse,
        reason: 'precondition: dave has no access to A',
      );

      final page = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: daveId,
        group: BeaconHierarchyChildGroup.active,
        first: 20,
      );
      expect(page.summaries, isEmpty);
      expect(page.nextCursor, isNull);
    }, skip: skipReason);

    test('admitted member of A gets B and D; non-admitted reader only B', () async {
      await seedTree();

      expect(
        await childIds(
          BeaconHierarchyTopology.aliceId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.beaconD],
      );

      // Bob reads A only through his admission to child B; he is not
      // admitted to A, so sibling D stays hidden.
      expect(
        await sqlPredicate(
          'beacon_effective_admission',
          BeaconHierarchyTopology.beaconA,
          BeaconHierarchyTopology.bobId,
        ),
        isFalse,
        reason: 'precondition: bob is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB],
      );
    }, skip: skipReason);

    test('viewer blocked by D owner does not get D', () async {
      await seedTree();
      await writer.execute(
        Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'blocker': BeaconHierarchyTopology.eveId,
          'blocked': BeaconHierarchyTopology.aliceId,
        },
      );

      expect(
        await childIds(
          BeaconHierarchyTopology.aliceId,
          BeaconHierarchyChildGroup.active,
        ),
        [BeaconHierarchyTopology.beaconB],
      );
    }, skip: skipReason);

    test('deleted child tombstone is listed only for admitted members of A', () async {
      await seedTree();
      const deletedId = 'Bhierdelete01';
      await insertPublishedChildBeacon(
        writer: writer,
        childId: deletedId,
        parentId: BeaconHierarchyTopology.beaconA,
        ownerId: BeaconHierarchyTopology.eveId,
        title: 'Deleted child',
        status: BeaconStatus.deleted,
        publishedAt: DateTime.utc(2026, 1, 2),
      );

      final aliceDeleted = await repository.listChildren(
        parentBeaconId: BeaconHierarchyTopology.beaconA,
        viewerId: BeaconHierarchyTopology.aliceId,
        group: BeaconHierarchyChildGroup.deleted,
        first: 20,
      );
      expect(aliceDeleted.summaries.map((s) => s.beaconId), [deletedId]);
      expect(aliceDeleted.summaries.single.isTombstone, isTrue);
      expect(aliceDeleted.summaries.single.title, isNull);

      expect(
        await childIds(
          BeaconHierarchyTopology.bobId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
        reason: 'bob reads A via child B but is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.frankId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
        reason: 'frank reads A via his help offer but is not admitted to A',
      );
      expect(
        await childIds(
          BeaconHierarchyTopology.daveId,
          BeaconHierarchyChildGroup.deleted,
        ),
        isEmpty,
      );
    }, skip: skipReason);
  });
}
