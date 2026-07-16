@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// SQL ↔ Dart policy parity — skipped when Postgres or m0098 is unavailable.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';
  var attentionSkipReason = skipReason;

  if (postgresReachable) {
    final env = _testEnv();
    final probe = TenturaDb(env);
    try {
      if (!await _hasVisibilityFunctions(probe)) {
        skipReason = 'm0098 schema (beacon_can_read_content) missing';
        attentionSkipReason = skipReason;
      } else if (!await _hasAttentionRelation(probe)) {
        attentionSkipReason =
            'm0117 schema (visible_attention_receipts) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late BeaconAccessRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = BeaconAccessRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.notification_outbox WHERE account_id LIKE 'Uvisparity%'",
      );
      await db.customStatement(
        "DELETE FROM public.inbox_item WHERE beacon_id = 'Bvisparity01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bvisparity01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon_help_offer WHERE beacon_id = 'Bvisparity01'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon_participant WHERE beacon_id = 'Bvisparity01'",
      );
      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject LIKE 'Uvisparity%' OR object LIKE 'Uvisparity%'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bvisparity01'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Uvisparity%' ''',
      );
    });
  }

  Future<void> seedUsers() async {
    final keyA = pgTestPublicKey('visparity', 1);
    final keyB = pgTestPublicKey('visparity', 2);
    final keyC = pgTestPublicKey('visparity', 3);
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Uvisparityauth', 'Author', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Uvisparityview', 'Viewer', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Uvisparitypeer', 'Peer', $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  public_key = EXCLUDED.public_key
''',
      [keyA, keyB, keyC],
    );
  }

  Future<void> insertBeacon({required int status}) async {
    await db.customStatement(
      r'''
INSERT INTO public.beacon (id, user_id, title, description, status, created_at, updated_at)
VALUES ('Bvisparity01', 'Uvisparityauth', 'Parity beacon', '', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
''',
      [status],
    );
  }

  Future<bool> sqlContent(String viewerId) =>
      repo.canReadContent(beaconId: 'Bvisparity01', viewerId: viewerId);

  Future<bool> sqlInvolvement(String viewerId) => repo.canReadInvolvement(
        beaconId: 'Bvisparity01',
        viewerId: viewerId,
      );

  Future<bool> sqlTombstone(String viewerId) => repo.canReadTombstone(
        beaconId: 'Bvisparity01',
        viewerId: viewerId,
      );

  test(
    'SQL content matches Dart policy for author, draft, deleted, mutual friend',
    () async {
      await seedUsers();

      await insertBeacon(status: BeaconStatus.draft.smallintValue);
      expect(await sqlContent('Uvisparityauth'), isTrue);
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(
        BeaconVisibility.canReadContent(
          BeaconContentVisibilityFacts(
            status: BeaconStatus.draft,
            isAuthor: true,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: false,
            isActiveHelpOfferer: false,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isTrue,
      );
      expect(
        BeaconVisibility.canReadContent(
          const BeaconContentVisibilityFacts(
            status: BeaconStatus.draft,
            isAuthor: false,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: false,
            isActiveHelpOfferer: false,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isFalse,
      );

      await insertBeacon(status: BeaconStatus.deleted.smallintValue);
      expect(await sqlContent('Uvisparityauth'), isFalse);
      expect(await sqlContent('Uvisparityview'), isFalse);

      await insertBeacon(status: BeaconStatus.open.smallintValue);
      await db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('Uvisparityview', 'Uvisparityauth', 1, now(), now()),
  ('Uvisparityauth', 'Uvisparityview', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadContent(
          const BeaconContentVisibilityFacts(
            status: BeaconStatus.open,
            isAuthor: false,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: false,
            isActiveHelpOfferer: false,
            isMutualFriendOfAuthor: true,
          ),
        ),
        isTrue,
      );
    },
    skip: skipReason,
  );

  test(
    'SQL involvement matches Dart for forward recipient and sender-only',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);

      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fvisparity01', 'Bvisparity01', 'Uvisparityauth', 'Uvisparityview', now()
)
ON CONFLICT (id) DO NOTHING
''',
      );

      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await sqlInvolvement('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadInvolvement(
          BeaconInvolvementVisibilityFacts(
            contentFacts: const BeaconContentVisibilityFacts(
              status: BeaconStatus.open,
              isAuthor: false,
              hasActiveForwardEdgeAsRecipient: true,
              isRoomAdmittedOrSteward: false,
              isActiveHelpOfferer: false,
              isMutualFriendOfAuthor: false,
            ),
            isOnActiveForwardEdge: true,
            isActiveHelpOfferer: false,
            isRoomAdmittedOrSteward: false,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isTrue,
      );

      expect(await sqlContent('Uvisparityauth'), isTrue);
      expect(await sqlInvolvement('Uvisparityauth'), isTrue);

      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'Fvisparity02', 'Bvisparity01', 'Uvisparityview', 'Uvisparitypeer', now(), now()
)
ON CONFLICT (id) DO NOTHING
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await sqlInvolvement('Uvisparityview'), isTrue);

      await db.customStatement(
        '''
UPDATE public.beacon_forward_edge
SET cancelled_at = now()
WHERE id = 'Fvisparity01'
''',
      );
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await sqlInvolvement('Uvisparityview'), isFalse);
    },
    skip: skipReason,
  );

  test(
    'SQL content matches Dart for help offer and room admission',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);

      await db.customStatement(
        '''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (
  'Bvisparity01', 'Uvisparityview', '', 0, now(), now()
)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = EXCLUDED.status
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadContent(
          const BeaconContentVisibilityFacts(
            status: BeaconStatus.open,
            isAuthor: false,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: false,
            isActiveHelpOfferer: true,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        '''
UPDATE public.beacon_help_offer SET status = 1
WHERE beacon_id = 'Bvisparity01' AND user_id = 'Uvisparityview'
''',
      );
      expect(await sqlContent('Uvisparityview'), isFalse);

      await db.customStatement(
        '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, room_access, created_at, updated_at
) VALUES (
  'Pvisparity01', 'Bvisparity01', 'Uvisparityview', 2, ${RoomAccessBits.admitted}, now(), now()
)
ON CONFLICT (id) DO UPDATE SET room_access = EXCLUDED.room_access
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await sqlInvolvement('Uvisparityview'), isTrue);
    },
    skip: skipReason,
  );

  test(
    'SQL content matches Dart for steward role and non-admitted room access',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);

      await db.customStatement(
        '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, room_access, created_at, updated_at
) VALUES (
  'Pvisparity02', 'Bvisparity01', 'Uvisparityview',
  ${BeaconParticipantRoleBits.steward}, ${RoomAccessBits.none}, now(), now()
)
ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role, room_access = EXCLUDED.room_access
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await sqlInvolvement('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadContent(
          const BeaconContentVisibilityFacts(
            status: BeaconStatus.open,
            isAuthor: false,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: true,
            isActiveHelpOfferer: false,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        '''
UPDATE public.beacon_participant
SET role = ${BeaconParticipantRoleBits.helper},
    room_access = ${RoomAccessBits.requested}
WHERE id = 'Pvisparity02'
''',
      );
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await sqlInvolvement('Uvisparityview'), isFalse);
      expect(
        BeaconVisibility.canReadContent(
          const BeaconContentVisibilityFacts(
            status: BeaconStatus.open,
            isAuthor: false,
            hasActiveForwardEdgeAsRecipient: false,
            isRoomAdmittedOrSteward: false,
            isActiveHelpOfferer: false,
            isMutualFriendOfAuthor: false,
          ),
        ),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'SQL involvement matches Dart for mutual friend and sender-only forward',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);

      await db.customStatement(
        '''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('Uvisparityview', 'Uvisparityauth', 1, now(), now()),
  ('Uvisparityauth', 'Uvisparityview', 1, now(), now())
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await sqlInvolvement('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvementFacts(
            contentFacts: const BeaconContentVisibilityFacts(
              status: BeaconStatus.open,
              isAuthor: false,
              hasActiveForwardEdgeAsRecipient: false,
              isRoomAdmittedOrSteward: false,
              isActiveHelpOfferer: false,
              isMutualFriendOfAuthor: true,
            ),
            isMutualFriendOfAuthor: true,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject = 'Uvisparityauth' AND object = 'Uvisparityview'",
      );
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await sqlInvolvement('Uvisparityview'), isFalse);

      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fvisparity03', 'Bvisparity01', 'Uvisparityview', 'Uvisparitypeer', now()
)
ON CONFLICT (id) DO NOTHING
''',
      );
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await sqlInvolvement('Uvisparityview'), isFalse);
      expect(
        BeaconVisibility.canReadInvolvement(
          _involvementFacts(
            contentFacts: const BeaconContentVisibilityFacts(
              status: BeaconStatus.open,
              isAuthor: false,
              hasActiveForwardEdgeAsRecipient: false,
              isRoomAdmittedOrSteward: false,
              isActiveHelpOfferer: false,
              isMutualFriendOfAuthor: false,
            ),
            isOnActiveForwardEdge: true,
          ),
        ),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'SQL tombstone matches Dart for deleted beacon durable rows',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);

      expect(await sqlTombstone('Uvisparityauth'), isFalse);
      expect(await sqlTombstone('Uvisparityview'), isFalse);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.open,
            isAuthor: true,
            hasInboxItem: true,
            hasForwardEdgeHistory: true,
            hasHelpOfferHistory: true,
            hasParticipantRow: true,
          ),
        ),
        isFalse,
      );

      await insertBeacon(status: BeaconStatus.deleted.smallintValue);

      expect(await sqlTombstone('Uvisparityauth'), isTrue);
      expect(await sqlTombstone('Uvisparityview'), isFalse);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: true,
            hasInboxItem: false,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: false,
            hasParticipantRow: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        '''
INSERT INTO public.inbox_item (
  user_id, beacon_id, context, forward_count, latest_forward_at, latest_note_preview
) VALUES (
  'Uvisparityview', 'Bvisparity01', 'Parity inbox', 0, now(), ''
)
ON CONFLICT (user_id, beacon_id) DO NOTHING
''',
      );
      expect(await sqlTombstone('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: true,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: false,
            hasParticipantRow: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        "DELETE FROM public.inbox_item WHERE user_id = 'Uvisparityview'",
      );
      expect(await sqlTombstone('Uvisparityview'), isFalse);

      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'Fvisparity04', 'Bvisparity01', 'Uvisparityauth', 'Uvisparityview', now(), now()
)
ON CONFLICT (id) DO NOTHING
''',
      );
      expect(await sqlTombstone('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: false,
            hasForwardEdgeHistory: true,
            hasHelpOfferHistory: false,
            hasParticipantRow: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE id = 'Fvisparity04'",
      );
      await db.customStatement(
        '''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (
  'Bvisparity01', 'Uvisparityview', '', 1, now(), now()
)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET status = EXCLUDED.status
''',
      );
      expect(await sqlTombstone('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: false,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: true,
            hasParticipantRow: false,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        "DELETE FROM public.beacon_help_offer WHERE beacon_id = 'Bvisparity01'",
      );
      await db.customStatement(
        '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, room_access, created_at, updated_at
) VALUES (
  'Pvisparity03', 'Bvisparity01', 'Uvisparityview',
  ${BeaconParticipantRoleBits.helper}, ${RoomAccessBits.requested}, now(), now()
)
ON CONFLICT (id) DO NOTHING
''',
      );
      expect(await sqlTombstone('Uvisparityview'), isTrue);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: false,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: false,
            hasParticipantRow: true,
          ),
        ),
        isTrue,
      );

      await db.customStatement(
        "DELETE FROM public.beacon_participant WHERE id = 'Pvisparity03'",
      );
      expect(await sqlTombstone('Uvisparitypeer'), isFalse);
      expect(
        BeaconVisibility.canReadTombstone(
          const BeaconTombstoneFacts(
            status: BeaconStatus.deleted,
            isAuthor: false,
            hasInboxItem: false,
            hasForwardEdgeHistory: false,
            hasHelpOfferHistory: false,
            hasParticipantRow: false,
          ),
        ),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'attention relation stays in parity with canonical content/tombstone SQL',
    () async {
      await seedUsers();
      await insertBeacon(status: BeaconStatus.open.smallintValue);
      await db.customStatement(
        '''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, beacon_id,
  source_event_key, destination_kind, presentation_key, access_policy
) VALUES (
  'Nvisparity01', 'Uvisparityview', 'coordination',
  'coordinationChanged', 'normal', 'Parity', 'Parity', '/parity',
  'visparity-dedup', 'Bvisparity01', 'visparity-source',
  'beacon', 'request_status_changed', 'beacon_content'
)
''',
      );

      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await _attentionRelationContains(db, 'Nvisparity01'), isFalse);

      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fvisparity01', 'Bvisparity01',
  'Uvisparityauth', 'Uvisparityview', now()
)
''',
      );
      expect(await sqlContent('Uvisparityview'), isTrue);
      expect(await _attentionRelationContains(db, 'Nvisparity01'), isTrue);

      await insertBeacon(status: BeaconStatus.deleted.smallintValue);
      expect(await sqlContent('Uvisparityview'), isFalse);
      expect(await sqlTombstone('Uvisparityview'), isTrue);
      expect(await _attentionRelationContains(db, 'Nvisparity01'), isFalse);

      await db.customStatement('''
UPDATE public.notification_outbox
SET access_policy = 'beacon_tombstone'
WHERE id = 'Nvisparity01'
''');
      expect(await _attentionRelationContains(db, 'Nvisparity01'), isTrue);
    },
    skip: attentionSkipReason,
  );
}

BeaconInvolvementVisibilityFacts _involvementFacts({
  required BeaconContentVisibilityFacts contentFacts,
  bool isOnActiveForwardEdge = false,
  bool isActiveHelpOfferer = false,
  bool isRoomAdmittedOrSteward = false,
  bool isMutualFriendOfAuthor = false,
}) =>
    BeaconInvolvementVisibilityFacts(
      contentFacts: contentFacts,
      isOnActiveForwardEdge: isOnActiveForwardEdge,
      isActiveHelpOfferer: isActiveHelpOfferer,
      isRoomAdmittedOrSteward: isRoomAdmittedOrSteward,
      isMutualFriendOfAuthor: isMutualFriendOfAuthor,
    );

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

Future<bool> _hasVisibilityFunctions(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'beacon_can_read_content'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _hasAttentionRelation(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'visible_attention_receipts'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _attentionRelationContains(TenturaDb db, String receiptId) async {
  final row = await db.customSelect(
    r'''
SELECT EXISTS (
  SELECT 1
  FROM public.visible_attention_receipts('Uvisparityview')
  WHERE receipt_id = $1
) AS visible
''',
    variables: [Variable<String>(receiptId)],
  ).getSingle();
  return row.read<bool>('visible');
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object catch (_) {
    return false;
  }
}
