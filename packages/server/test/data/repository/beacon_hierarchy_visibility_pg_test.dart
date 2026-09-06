@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/exception.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import 'beacon_hierarchy_pg_helpers.dart';
import 'beacon_hierarchy_visibility_pg_support.dart';

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon hierarchy visibility PG test';

  group('beacon hierarchy visibility — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconAccessRepository access;
    late BeaconHierarchyRepository hierarchy;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      access = BeaconAccessRepository(session.db);
      hierarchy = BeaconHierarchyRepository(session.db);
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

    Future<void> _reseedParticipantsAfterHierarchyTree(Connection writer) async {
      for (final row in <(String, String, String, int)>[
        ('PhierbobB01', BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.bobId, RoomAccessBits.admitted),
        ('PhiercarolC01', BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.carolId, RoomAccessBits.admitted),
        ('PhieraliceA01', BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.aliceId, RoomAccessBits.admitted),
      ]) {
        await writer.execute(
          Sql.named(r'''
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
            'roomAccess': row.$4,
          },
        );
      }
    }

    Future<void> seedTree() async {
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
      await _reseedParticipantsAfterHierarchyTree(writer);
    }

    Future<void> admitFrankToParentAOnly() async {
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
          'roomAccess': RoomAccessBits.admitted,
        },
      );
    }

    Future<bool> effectiveAdmission(String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named(
          'SELECT public.beacon_effective_admission(@beaconId, @viewerId)',
        ),
        parameters: {'beaconId': beaconId, 'viewerId': viewerId},
      );
      return row.first.first as bool;
    }

    test('beacon_effective_admission matches A/B/C/D fixture roles', () async {
      await seedTree();

      expect(
        await effectiveAdmission(
          BeaconHierarchyTopology.beaconA,
          BeaconHierarchyTopology.aliceId,
        ),
        isTrue,
        reason: 'author',
      );
      expect(
        await effectiveAdmission(
          BeaconHierarchyTopology.beaconB,
          BeaconHierarchyTopology.bobId,
        ),
        isTrue,
        reason: 'child owner',
      );
      expect(
        await effectiveAdmission(
          BeaconHierarchyTopology.beaconC,
          BeaconHierarchyTopology.carolId,
        ),
        isTrue,
        reason: 'admitted participant',
      );
      expect(
        await effectiveAdmission(
          BeaconHierarchyTopology.beaconD,
          BeaconHierarchyTopology.eveId,
        ),
        isTrue,
        reason: 'sibling owner',
      );
      expect(
        await effectiveAdmission(
          BeaconHierarchyTopology.beaconA,
          BeaconHierarchyTopology.frankId,
        ),
        isFalse,
        reason: 'help offer alone is not effective admission',
      );
    }, skip: skipReason);

    test(
      'hierarchy-only viewer gets linked detail on child but not content',
      () async {
        await seedTree();
        await admitFrankToParentAOnly();

        final childId = BeaconHierarchyTopology.beaconB;
        final viewerId = BeaconHierarchyTopology.frankId;

        expect(await access.canReadContent(beaconId: childId, viewerId: viewerId),
            isFalse);
        expect(
          await access.canReadLinkedDetail(beaconId: childId, viewerId: viewerId),
          isTrue,
        );
        expect(
          await effectiveAdmission(childId, viewerId),
          isFalse,
          reason: 'no transitive effective admission',
        );
      },
      skip: skipReason,
    );

    test('block hides linked detail in both directions', () async {
      await seedTree();
      await admitFrankToParentAOnly();

      final childId = BeaconHierarchyTopology.beaconB;
      final frankId = BeaconHierarchyTopology.frankId;
      final bobId = BeaconHierarchyTopology.bobId;

      await writer.execute(
        Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
        parameters: {'blocker': bobId, 'blocked': frankId},
      );
      expect(
        await access.canReadLinkedDetail(beaconId: childId, viewerId: frankId),
        isFalse,
        reason: 'child owner blocked viewer',
      );

      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id = '$bobId'",
      );
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
        parameters: {'blocker': frankId, 'blocked': bobId},
      );
      expect(
        await access.canReadLinkedDetail(beaconId: childId, viewerId: frankId),
        isFalse,
        reason: 'viewer blocked child owner',
      );
    }, skip: skipReason);

    test('revoked parent admission removes linked detail without residue', () async {
      await seedTree();
      await admitFrankToParentAOnly();

      final childId = BeaconHierarchyTopology.beaconB;
      final frankId = BeaconHierarchyTopology.frankId;

      expect(
        await access.canReadLinkedDetail(beaconId: childId, viewerId: frankId),
        isTrue,
      );

      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE id = 'PhierfrankA01'",
      );
      expect(
        await access.canReadLinkedDetail(beaconId: childId, viewerId: frankId),
        isFalse,
      );
      expect(await access.canReadContent(beaconId: childId, viewerId: frankId),
          isFalse);
    }, skip: skipReason);

    test('no transitive linked-detail grant across grandchild', () async {
      await seedTree();
      await admitFrankToParentAOnly();

      final grandchildId = BeaconHierarchyTopology.beaconC;
      final frankId = BeaconHierarchyTopology.frankId;

      expect(
        await access.canReadLinkedDetail(
          beaconId: grandchildId,
          viewerId: frankId,
        ),
        isFalse,
      );
      expect(
        await access.canReadContent(beaconId: grandchildId, viewerId: frankId),
        isFalse,
      );
    }, skip: skipReason);

    group('non-transitivity — production call sites refuse hierarchy-only viewer',
        () {
      late HierarchyOnlyViewerHarness harness;

      setUp(() async {
        await seedTree();
        await admitFrankToParentAOnly();
        harness = HierarchyOnlyViewerHarness(
          access: access,
          childBeaconId: BeaconHierarchyTopology.beaconB,
          hierarchyOnlyViewerId: BeaconHierarchyTopology.frankId,
        );
      });

      test('help_offer_case offerHelp and withdrawHelp', () async {
        final case_ = harness.buildHelpOfferCase();
        await expectLater(
          case_.offerHelp(
            beaconId: harness.childBeaconId,
            userId: harness.hierarchyOnlyViewerId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
        await expectLater(
          case_.withdraw(
            beaconId: harness.childBeaconId,
            userId: harness.hierarchyOnlyViewerId,
            withdrawReason: 'other',
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('forward_case forward cannot mint child content access', () async {
        final case_ = harness.buildForwardCase();
        await expectLater(
          case_.forward(
            beaconId: harness.childBeaconId,
            senderId: harness.hierarchyOnlyViewerId,
            recipientIds: [BeaconHierarchyTopology.carolId],
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('assertBeaconLineageSourceVisible', () async {
        await expectLater(
          assertBeaconLineageSourceVisible(
            guard: access,
            beaconId: harness.childBeaconId,
            userId: harness.hierarchyOnlyViewerId,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });

      test('invitation_case create with beacon scope', () async {
        final case_ = harness.buildInvitationCase();
        await expectLater(
          case_.create(
            userId: harness.hierarchyOnlyViewerId,
            addresseeName: 'target',
            beaconId: harness.childBeaconId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('coordination_case helpOffersWithCoordination', () async {
        final case_ = harness.buildCoordinationCase();
        await expectLater(
          case_.helpOffersWithCoordination(
            beaconId: harness.childBeaconId,
            viewerId: harness.hierarchyOnlyViewerId,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });
    }, skip: skipReason);

    test('lockMutationScope serializes concurrent transactions', () async {
      await seedTree();

      final env = target.databaseEnv;
      final conn1 = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      final conn2 = await Connection.open(
        env.pgEndpoint,
        settings: env.pgEndpointSettings,
      );
      try {
        await conn1.execute('BEGIN');
        await conn1.execute(
          r"SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
        );

        var secondCompleted = false;
        final secondLock = () async {
          await conn2.execute('BEGIN');
          await conn2.execute(
            r"SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );
          secondCompleted = true;
          await conn2.execute('COMMIT');
        }();

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(secondCompleted, isFalse);

        await conn1.execute('COMMIT');
        await secondLock.timeout(const Duration(seconds: 5));
        expect(secondCompleted, isTrue);
      } finally {
        await conn1.close();
        await conn2.close();
      }
    }, skip: skipReason);

    test('repository lockMutationScope runs inside caller transaction', () async {
      await seedTree();
      await fixture.db.transaction(() async {
        await hierarchy.lockMutationScope();
        final row = await fixture.db.customSelect(
          r'''
SELECT EXISTS (
  SELECT 1 FROM pg_locks
  WHERE locktype = 'advisory'
    AND mode = 'ExclusiveLock'
    AND granted = true
) AS held
''',
        ).getSingle();
        expect(row.read<bool>('held'), isTrue);
      });
    }, skip: skipReason);
  });
}
