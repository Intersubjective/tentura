@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/mock/trust_evidence_repository_mock.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Issue #145: unconsumed child invite after leaving parent must not restore
/// parent read access (content or hierarchy-linked detail).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ISSUE_145_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_issue_145',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late UserRepository userRepo;
  late BeaconAccessRepository access;

  const authorId = 'U145author01';
  const guestId = 'U145guest001';
  const parentId = 'B145parent01';
  const childId = 'B145child001';
  const parentEdgeId = 'F145parent01';
  const inviteId = 'I145invite01';

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      final env = Env(
        environment: Environment.test,
        pgHost: target.databaseEnv.pgHost,
        pgPort: target.databaseEnv.pgPort,
        pgDatabase: target.databaseName,
        pgUsername: target.databaseEnv.pgUsername,
        pgPassword: target.databaseEnv.pgPassword,
        printEnv: false,
        isDebugModeOn: false,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      );
      userRepo = UserRepository(
        env,
        db,
        const TrustEvidenceRepositoryMock(),
        InviteGenealogyRepository(env, db, UserBlockRepository(env, db)),
        InviteSeedPromptRepository(db),
      );
      access = BeaconAccessRepository(db);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id IN ('$parentId', '$childId')",
      );
      await db.customStatement(
        "DELETE FROM public.invitation WHERE id = '$inviteId'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id IN ('$parentId', '$childId')",
      );
      await db.customStatement(
        "DELETE FROM public.user_contact WHERE viewer_id = '$authorId' AND subject_id = '$guestId'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$authorId', '$guestId')''',
      );
    });
  }

  Future<bool> canReadContent(String beaconId, String viewerId) =>
      access.canReadContent(beaconId: beaconId, viewerId: viewerId);

  Future<bool> canReadLinkedDetail(String beaconId, String viewerId) =>
      access.canReadLinkedDetail(beaconId: beaconId, viewerId: viewerId);

  group('issue #145 stale child invite after parent leave', () {
    test(
      'after child invite consumed, leaving parent must drop parent linked access',
      () async {
        final keyAuthor = pgTestPublicKey('i145', 3);
        final keyGuest = pgTestPublicKey('i145', 4);
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$authorId', 'Author', '$keyAuthor', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$guestId', 'Guest', '$keyGuest', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.beacon (
  id, user_id, parent_beacon_id, title, description, status,
  published_at, created_at, updated_at
) VALUES
  ('$parentId', '$authorId', NULL, 'Parent request', '', 0,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$childId', '$authorId', '$parentId', 'Child request', '', 0,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at
) VALUES (
  '$parentEdgeId', '$parentId', '$authorId', '$guestId', NULL,
  '2026-01-01T00:00:01Z'
)
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.invitation (
  id, user_id, beacon_id, parent_forward_edge_id, addressee_name,
  created_at, updated_at
) VALUES (
  '$inviteId', '$authorId', '$childId', '$parentEdgeId', 'Guest',
  now(), now()
)
ON CONFLICT (id) DO UPDATE SET
  invited_id = NULL,
  invite_origin = NULL,
  accepted_at = NULL,
  beacon_id = EXCLUDED.beacon_id,
  parent_forward_edge_id = EXCLUDED.parent_forward_edge_id
''',
        );

        expect(
          await userRepo.bindMutual(
            invitationId: inviteId,
            userId: guestId,
            bindFriendship: false,
          ),
          isTrue,
        );
        expect(await canReadContent(childId, guestId), isTrue);
        expect(await canReadContent(parentId, guestId), isTrue);

        await db.customStatement(
          '''
UPDATE public.beacon_forward_edge
SET cancelled_at = '2026-01-02T00:00:00Z'
WHERE id = '$parentEdgeId'
''',
        );

        expect(
          await canReadContent(parentId, guestId),
          isFalse,
          reason: 'guest left parent forward edge on parent beacon',
        );
        expect(
          await canReadLinkedDetail(parentId, guestId),
          isFalse,
          reason:
              'child membership must not keep parent hierarchy access after leave',
        );
      },
      skip: skipReason,
    );

    test(
      'unconsumed child invite must not be consumable after parent leave '
      '(issue #145)',
      () async {
        final keyAuthor = pgTestPublicKey('i145', 1);
        final keyGuest = pgTestPublicKey('i145', 2);
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$authorId', 'Author', '$keyAuthor', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$guestId', 'Guest', '$keyGuest', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.beacon (
  id, user_id, parent_beacon_id, title, description, status,
  published_at, created_at, updated_at
) VALUES
  ('$parentId', '$authorId', NULL, 'Parent request', '', 0,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$childId', '$authorId', '$parentId', 'Child request', '', 0,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, parent_edge_id, created_at
) VALUES (
  '$parentEdgeId', '$parentId', '$authorId', '$guestId', NULL,
  '2026-01-01T00:00:01Z'
)
ON CONFLICT (id) DO NOTHING
''',
        );
        await db.customStatement(
          '''
INSERT INTO public.invitation (
  id, user_id, beacon_id, parent_forward_edge_id, addressee_name,
  created_at, updated_at
) VALUES (
  '$inviteId', '$authorId', '$childId', '$parentEdgeId', 'Guest',
  now(), now()
)
ON CONFLICT (id) DO UPDATE SET
  invited_id = NULL,
  invite_origin = NULL,
  accepted_at = NULL,
  beacon_id = EXCLUDED.beacon_id,
  parent_forward_edge_id = EXCLUDED.parent_forward_edge_id
''',
        );

        expect(await canReadContent(parentId, guestId), isTrue);

        await db.customStatement(
          '''
UPDATE public.beacon_forward_edge
SET cancelled_at = '2026-01-02T00:00:00Z'
WHERE id = '$parentEdgeId'
''',
        );

        expect(
          await canReadContent(parentId, guestId),
          isFalse,
          reason: 'guest left parent (inbound forward cancelled)',
        );
        expect(
          await canReadLinkedDetail(parentId, guestId),
          isFalse,
          reason: 'no child admission yet',
        );

        expect(
          await userRepo.bindMutual(
            invitationId: inviteId,
            userId: guestId,
            bindFriendship: false,
          ),
          isFalse,
          reason:
              'invite anchored to abandoned parent admission must not consume',
        );

        expect(
          await canReadContent(parentId, guestId),
          isFalse,
          reason: 'stale child invite must not recreate parent forward edge',
        );
        expect(
          await canReadLinkedDetail(parentId, guestId),
          isFalse,
          reason: 'child join via stale invite must not imply parent access',
        );
      },
      skip: skipReason,
    );
  });
}
