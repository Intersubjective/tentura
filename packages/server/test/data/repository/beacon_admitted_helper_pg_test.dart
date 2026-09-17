@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';
import 'beacon_hierarchy_pg_helpers.dart';

/// m0174: admitted-helper view + can_read_admitted_helpers SQL.
Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for admitted-helper PG test';

  group('beacon admitted helper — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconAccessRepository access;

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
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      for (final (i, id) in BeaconHierarchyTopology.allUserIds.indexed) {
        await writer.execute(
          Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
          parameters: {
            'id': id,
            'publicKey': pgTestPublicKey('admhlp', i + 1),
          },
        );
      }
      await fixture.seedFullTopology();
      await seedPublishedHierarchyTree(writer);
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

    Future<bool> sqlAdmittedHelpers(String beaconId, String viewerId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT public.beacon_can_read_admitted_helpers(@b, @v) AS allowed',
        ),
        parameters: {'b': beaconId, 'v': viewerId},
      );
      return rows.first.first! as bool;
    }

    Future<Set<String>> helperIds(String beaconId) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT user_id FROM public.beacon_admitted_helper WHERE beacon_id = @b',
        ),
        parameters: {'b': beaconId},
      );
      return {for (final r in rows) r.first! as String};
    }

    Future<void> admit({
      required String id,
      required String beaconId,
      required String userId,
      int role = BeaconParticipantRoleBits.helper,
    }) => writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, @role, 5, @access,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET
  role = EXCLUDED.role,
  room_access = EXCLUDED.room_access,
  status = EXCLUDED.status
'''),
      parameters: {
        'id': id,
        'beaconId': beaconId,
        'userId': userId,
        'role': role,
        'access': RoomAccessBits.admitted,
      },
    );

    test(
      'SQL admitted-helpers matches content; discover sees helpers right but not involvement',
      () async {
        final beaconId = BeaconHierarchyTopology.beaconB;
        final author = BeaconHierarchyTopology.bobId;
        final discoverer = BeaconHierarchyTopology.frankId;

        // Forward-sender-only has no content / admitted-helpers path.
        expect(await sqlAdmittedHelpers(beaconId, discoverer), isFalse);

        await writer.execute(
          Sql.named(r'''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  (@a, @b, 1, now(), now()),
  (@b, @a, 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
'''),
          parameters: {'a': author, 'b': discoverer},
        );
        await writer.execute(
          Sql.named(
            'UPDATE public.beacon SET is_discoverable = true WHERE id = @id',
          ),
          parameters: {'id': beaconId},
        );

        expect(await sqlAdmittedHelpers(beaconId, discoverer), isTrue);
        expect(
          await access.canReadContent(
            beaconId: beaconId,
            viewerId: discoverer,
          ),
          isTrue,
        );
        expect(
          await access.canReadInvolvement(
            beaconId: beaconId,
            viewerId: discoverer,
          ),
          isFalse,
        );
        expect(
          BeaconVisibility.canReadAdmittedHelpers(
            const BeaconContentVisibilityFacts(
              status: BeaconStatus.open,
              isAuthor: false,
              hasActiveForwardEdgeAsRecipient: false,
              isRoomAdmittedOrSteward: false,
              isActiveHelpOfferer: false,
              isDiscoverable: true,
              isPublished: true,
              isMutuallyVisibleWithAuthor: true,
            ),
          ),
          isTrue,
        );
      },
      skip: skipReason,
    );

    test(
      'view includes admitted helper and admitted steward; excludes author',
      () async {
        final beaconId = BeaconHierarchyTopology.beaconB;
        final author = BeaconHierarchyTopology.bobId;
        final helper = BeaconHierarchyTopology.aliceId;
        final stewardHelper = BeaconHierarchyTopology.carolId;

        await admit(id: 'Pahlhelper01', beaconId: beaconId, userId: helper);
        await admit(
          id: 'Pahlsteward01',
          beaconId: beaconId,
          userId: stewardHelper,
          role: BeaconParticipantRoleBits.steward,
        );

        final ids = await helperIds(beaconId);
        expect(ids, containsAll([helper, stewardHelper]));
        expect(ids, isNot(contains(author)));
      },
      skip: skipReason,
    );

    test(
      'view excludes unacked offerer and steward without admission',
      () async {
        final beaconId = BeaconHierarchyTopology.beaconB;
        final offerer = BeaconHierarchyTopology.aliceId;
        final stewardOnly = BeaconHierarchyTopology.carolId;

        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (
  @beaconId, @userId, 'offer', 0, now(), now()
)
ON CONFLICT DO NOTHING
'''),
          parameters: {'beaconId': beaconId, 'userId': offerer},
        );
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES (@beaconId, @userId)
ON CONFLICT DO NOTHING
'''),
          parameters: {'beaconId': beaconId, 'userId': stewardOnly},
        );

        final ids = await helperIds(beaconId);
        expect(ids, isNot(contains(offerer)));
        expect(ids, isNot(contains(stewardOnly)));
      },
      skip: skipReason,
    );

    test('view excludes helper blocked by author', () async {
      final beaconId = BeaconHierarchyTopology.beaconB;
      final author = BeaconHierarchyTopology.bobId;
      final helper = BeaconHierarchyTopology.aliceId;

      await admit(id: 'Pahlblock01', beaconId: beaconId, userId: helper);
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, created_at)
VALUES (@blocker, @blocked, now())
ON CONFLICT DO NOTHING
'''),
        parameters: {'blocker': author, 'blocked': helper},
      );

      expect(await helperIds(beaconId), isNot(contains(helper)));
    }, skip: skipReason);
  });
}
