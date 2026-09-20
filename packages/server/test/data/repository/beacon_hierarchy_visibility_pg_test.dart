@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/recording_commitment_repository.dart';
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
    var sessionOpened = false;
    BeaconHierarchyDisposablePgTarget? createdTarget;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      createdTarget = target;
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      access = BeaconAccessRepository(session.db);
      hierarchy = BeaconHierarchyRepository(session.db);
      sessionOpened = true;
    });

    tearDown(() async {
      if (skipReason != false || !sessionOpened) {
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
      if (sessionOpened) {
        await fixture.db.close();
        await writer.close();
      }
      await createdTarget?.drop();
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

    Future<int> accessReasons(String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.beacon_access_reasons(@beaconId, @viewerId)'),
        parameters: {'beaconId': beaconId, 'viewerId': viewerId},
      );
      return row.first.first! as int;
    }

    test(
      'parent member reads child content through context grant',
      () async {
        await seedTree();
        await admitFrankToParentAOnly();

        final childId = BeaconHierarchyTopology.beaconB;
        final viewerId = BeaconHierarchyTopology.frankId;

        expect(await access.canReadContent(beaconId: childId, viewerId: viewerId),
            isTrue);
        expect(
          await accessReasons(childId, viewerId),
          BeaconAccessReason.contextChild.bit,
        );
        expect(
          await effectiveAdmission(childId, viewerId),
          isFalse,
          reason: 'no transitive effective admission',
        );
      },
      skip: skipReason,
    );

    test('block hides context content in both directions', () async {
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
        await access.canReadContent(beaconId: childId, viewerId: frankId),
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
        await access.canReadContent(beaconId: childId, viewerId: frankId),
        isFalse,
        reason: 'viewer blocked child owner',
      );
    }, skip: skipReason);

    test('revoked parent admission removes context content without residue', () async {
      await seedTree();
      await admitFrankToParentAOnly();

      final childId = BeaconHierarchyTopology.beaconB;
      final frankId = BeaconHierarchyTopology.frankId;

      expect(
        await access.canReadContent(beaconId: childId, viewerId: frankId),
        isTrue,
      );

      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE id = 'PhierfrankA01'",
      );
      expect(
        await access.canReadContent(beaconId: childId, viewerId: frankId),
        isFalse,
      );
      expect(await accessReasons(childId, frankId), 0);
    }, skip: skipReason);

    test(
      'context reaches one level down but any level up',
      () async {
        await seedTree();
        await admitFrankToParentAOnly();

        final grandparentId = BeaconHierarchyTopology.beaconA;
        final grandchildId = BeaconHierarchyTopology.beaconC;
        final frankId = BeaconHierarchyTopology.frankId;
        final carolId = BeaconHierarchyTopology.carolId;

        expect(
          await access.canReadContent(
            beaconId: grandchildId,
            viewerId: frankId,
          ),
          isFalse,
          reason: 'grandparent member does not see grandchild',
        );
        expect(await accessReasons(grandchildId, frankId), 0);
        expect(
          await access.canReadContent(
            beaconId: grandparentId,
            viewerId: carolId,
          ),
          isTrue,
          reason: 'grandchild member sees grandparent (contextAncestor)',
        );
        expect(
          await accessReasons(grandparentId, carolId),
          BeaconAccessReason.contextAncestor.bit,
        );
      },
      skip: skipReason,
    );

    group('hierarchy context observer is an ordinary observer (D2)', () {
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

      test('help_offer_case offerHelp and withdrawHelp succeed', () async {
        final case_ = harness.buildHelpOfferCase();
        await case_.offerHelp(
          beaconId: harness.childBeaconId,
          userId: harness.hierarchyOnlyViewerId,
        );
        await case_.withdraw(
          beaconId: harness.childBeaconId,
          userId: harness.hierarchyOnlyViewerId,
          withdrawReason: 'other',
        );
      });

      test(
        'help_offer_case content-authorized child owner passes canReadContent gate',
        () async {
          final childId = harness.childBeaconId;
          final bobId = BeaconHierarchyTopology.bobId;
          expect(
            await access.canReadContent(beaconId: childId, viewerId: bobId),
            isTrue,
          );
          final case_ = harness.buildHelpOfferCase();
          await expectLater(
            case_.offerHelp(beaconId: childId, userId: bobId),
            throwsA(
              isA<HelpOfferCoordinationException>().having(
                (e) =>
                    (e.code as HelpOfferCoordinationExceptionCodes)
                        .exceptionCode,
                'code',
                HelpOfferCoordinationExceptionCode.authorCannotCommit,
              ),
            ),
          );
        },
      );

      test('help_offer_case rolls back commitment when upsert fails after guard',
          () async {
        final childId = harness.childBeaconId;
        final bobId = BeaconHierarchyTopology.bobId;
        expect(
          await access.canReadContent(beaconId: childId, viewerId: bobId),
          isTrue,
        );
        final commitmentRepo = RecordingCommitmentRepository();
        final case_ = harness.buildHelpOfferCaseWithInjectedUpsertFailure(
          commitmentRepo: commitmentRepo,
        );
        await expectLater(
          case_.offerHelp(beaconId: childId, userId: bobId),
          throwsA(isA<StateError>()),
        );
        expect(commitmentRepo.recordCalls, isEmpty);
      });

      test('forward_case forward makes recipient a forwarded observer only',
          () async {
        // eve owns sibling D only, so she has no context on B.
        final recipientId = BeaconHierarchyTopology.eveId;
        final childId = harness.childBeaconId;
        final senderId = harness.hierarchyOnlyViewerId;
        expect(await accessReasons(childId, recipientId), 0);
        final case_ = harness.buildForwardCase(
          onEdgesCreated: (recipientIds) async {
            for (final id in recipientIds) {
              await writer.execute(
                Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'FhierctxB02', @beaconId, @senderId, @recipientId, '2026-01-02T00:00:00Z'
)
'''),
                parameters: {
                  'beaconId': childId,
                  'senderId': senderId,
                  'recipientId': id,
                },
              );
            }
          },
        );
        final result = await case_.forward(
          beaconId: childId,
          senderId: senderId,
          recipientIds: [recipientId],
        );
        expect(result.deliveredRecipientIds, [recipientId]);
        expect(
          await accessReasons(childId, recipientId),
          BeaconAccessReason.forwarded.bit,
          reason: 'S4-10: forwarding never grants context bits',
        );
      });

      test('assertBeaconLineageSourceVisible accepts context observer',
          () async {
        await assertBeaconLineageSourceVisible(
          guard: access,
          beaconId: harness.childBeaconId,
          userId: harness.hierarchyOnlyViewerId,
        );
      });

      test('invitation_case create with beacon scope succeeds', () async {
        final case_ = harness.buildInvitationCase();
        final invitation = await case_.create(
          userId: harness.hierarchyOnlyViewerId,
          addresseeName: 'target',
          beaconId: harness.childBeaconId,
        );
        expect(invitation.beaconId, harness.childBeaconId);
      });

      test('coordination_case helpOffersWithCoordination still refuses '
          'an uninvolved context observer', () async {
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
  SELECT 1
  FROM pg_locks l
  CROSS JOIN (
    SELECT hashtextextended('tentura.beacon_hierarchy.v1', 0) AS key
  ) k
  WHERE l.locktype = 'advisory'
    AND l.mode = 'ExclusiveLock'
    AND l.granted = true
    -- Match this repository's own key, in this database. `pg_locks` reports
    -- the whole cluster and `migrateDbSchema` holds an advisory ExclusiveLock
    -- for the length of a schema build, so the unqualified form was satisfied
    -- by any other disposable database that happened to be migrating.
    AND ((l.classid::bigint << 32) | (l.objid::bigint & 4294967295)) = k.key
    AND l.database =
        (SELECT oid FROM pg_database WHERE datname = current_database())
) AS held
''',
        ).getSingle();
        expect(row.read<bool>('held'), isTrue);
      });
    }, skip: skipReason);
  });
}
