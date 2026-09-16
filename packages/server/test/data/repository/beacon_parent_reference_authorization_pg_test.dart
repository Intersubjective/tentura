@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';
import 'beacon_hierarchy_pg_helpers.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beaconParentReference authorization PG test';

  group('BeaconHierarchyRepository.loadParentReference authorization — disposable Postgres', () {
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

    // Every persona in BeaconHierarchyTopology ends up a member of some
    // beacon in the A/B/C/D tree once issue-146 T09's contextChild/
    // contextAncestor grants apply (e.g. dave owns grandchild C, a
    // descendant of both A and B). Use a freshly seeded, wholly unconnected
    // user for tests that need a genuine stranger to the whole tree.
    Future<String> seedStranger() async {
      const strangerId = 'Uhierstranger';
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': strangerId,
          'publicKey': pgTestPublicKey('stranger', 1),
        },
      );
      return strangerId;
    }

    Future<bool> sqlPredicate(String fn, String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.$fn(@beaconId, @viewerId)'),
        parameters: {'beaconId': beaconId, 'viewerId': viewerId},
      );
      return row.first.first! as bool;
    }

    Future<BeaconParentReference> parentOfB(String viewerId) =>
        repository.loadParentReference(
          childBeaconId: BeaconHierarchyTopology.beaconB,
          viewerId: viewerId,
        );

    test('member of B who is not admitted to A gets the parent link', () async {
      await seedTree();
      const bobId = BeaconHierarchyTopology.bobId;
      expect(
        await sqlPredicate(
          'beacon_effective_admission',
          BeaconHierarchyTopology.beaconA,
          bobId,
        ),
        isFalse,
        reason: 'precondition: bob is not admitted to A',
      );

      final ref = await parentOfB(bobId);
      expect(ref.state, BeaconParentReferenceState.available);
      expect(ref.beaconId, BeaconHierarchyTopology.beaconA);
      expect(ref.title, 'Request A');
    }, skip: skipReason);

    test('viewer who cannot read B gets no reference', () async {
      await seedTree();
      // A fresh, wholly unconnected stranger has no admission, help offer,
      // forward or membership touching B (or anything in the tree).
      final strangerId = await seedStranger();
      expect(
        await sqlPredicate(
          'beacon_can_read_content',
          BeaconHierarchyTopology.beaconB,
          strangerId,
        ),
        isFalse,
        reason: 'precondition: the stranger cannot read B',
      );

      final ref = await parentOfB(strangerId);
      expect(ref.state, BeaconParentReferenceState.none);
      expect(ref.beaconId, isNull);
      expect(ref.title, isNull);
    }, skip: skipReason);

    test('forward recipient of B with no path to A gets an unavailable reference', () async {
      await seedTree();
      final strangerId = await seedStranger();
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'FhierfwdBdave01', @beaconId, @senderId, @recipientId,
  '2026-01-02T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
        parameters: {
          'beaconId': BeaconHierarchyTopology.beaconB,
          'senderId': BeaconHierarchyTopology.bobId,
          'recipientId': strangerId,
        },
      );
      expect(
        await sqlPredicate(
          'beacon_can_read_content',
          BeaconHierarchyTopology.beaconB,
          strangerId,
        ),
        isTrue,
        reason: 'precondition: the forward lets the stranger read B',
      );
      expect(
        await sqlPredicate(
          'beacon_can_read_linked_detail',
          BeaconHierarchyTopology.beaconA,
          strangerId,
        ),
        isFalse,
        reason: 'precondition: the stranger has no path to A',
      );

      final ref = await parentOfB(strangerId);
      expect(ref.state, BeaconParentReferenceState.unavailable);
      expect(ref.beaconId, isNull);
      expect(ref.title, isNull);
    }, skip: skipReason);
  });
}
