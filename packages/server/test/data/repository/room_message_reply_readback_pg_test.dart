@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_user_block_repository.dart';
import '../../support/pg_test_public_keys.dart';

class _PgFakeFactCards extends Fake
    implements BeaconFactCardRepositoryPort {}

class _PgFakeImages extends Fake implements ImageRepositoryPort {}

class _PgFakeTasks extends Fake implements TaskRepositoryPort {}

class _PgFakeRemoteStorage extends Fake implements RemoteStoragePort {}

class _PgFakePolling extends Fake implements PollingRepositoryPort {}

class _PgFakeUploadQuota extends Fake implements UploadQuotaRepositoryPort {}

Future<void> main() async {
  final env = Env(
    environment: Environment.test,
    pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
    pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
    pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
    printEnv: false,
    isDebugModeOn: false,
  );
  final reachable = await _canConnect(env);
  final skipReason =
      reachable ? false : 'Postgres not reachable for reply readback test';

  const beaconId = 'Breplypg00001';
  const otherBeaconId = 'Breplypgother1';
  const parentAuthorId = 'Ureplypg00001';
  const replyAuthorId = 'Ureplypg00002';
  const newMentionUserId = 'Ureplypg00003';
  const viewerId = parentAuthorId;

  late TenturaDb database;
  late BeaconRoomRepository room;

  if (skipReason == false) {
    setUpAll(() async {
      database = TenturaDb(env);
      room = BeaconRoomRepository(database);
    });

    tearDownAll(() async {
      await database.close();
    });

    tearDown(() async {
      await database.customStatement(
        'DELETE FROM public.attention_channel_delivery '
        'WHERE account_id LIKE \'Ureplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public.attention_occurrence_recipient '
        'WHERE account_id LIKE \'Ureplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_room_message_attachment '
        'WHERE message_id LIKE \'Rreplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_room_message WHERE id LIKE \'Rreplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon_participant '
        'WHERE beacon_id LIKE \'Breplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public.beacon WHERE id LIKE \'Breplypg%\'',
      );
      await database.customStatement(
        'DELETE FROM public."user" WHERE id LIKE \'Ureplypg%\'',
      );
    });
  }

  Future<void> seedUser(String id, int slot, {String? handle}) async {
    final key = pgTestPublicKey('replypg', slot);
    final handleSql = handle == null ? 'NULL' : "'$handle'";
    await database.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, handle)
VALUES ('$id', '$id', '$key', $handleSql)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  handle = EXCLUDED.handle
''',
    );
  }

  Future<void> seedBeacon(String id, String ownerId) async {
    await database.customStatement(
      '''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('$id', '$ownerId', 'Reply PG', 'Reply readback contract')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<void> seedParticipant({
    required String participantId,
    required String beacon,
    required String userId,
  }) async {
    await database.customStatement(
      '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access
) VALUES ('$participantId', '$beacon', '$userId', 2, 0, 3)
ON CONFLICT DO NOTHING
''',
    );
  }

  Future<void> seedBaseRoom() async {
    await seedUser(parentAuthorId, 1);
    await seedUser(replyAuthorId, 2);
    await seedUser(newMentionUserId, 3, handle: 'newmention');
    await seedBeacon(beaconId, parentAuthorId);
    await seedBeacon(otherBeaconId, parentAuthorId);
    await seedParticipant(
      participantId: 'Preplypg00001',
      beacon: beaconId,
      userId: parentAuthorId,
    );
    await seedParticipant(
      participantId: 'Preplypg00002',
      beacon: beaconId,
      userId: replyAuthorId,
    );
    await seedParticipant(
      participantId: 'Preplypg00003',
      beacon: beaconId,
      userId: newMentionUserId,
    );
  }

  void expectReplyFields(
    Map<String, Object?> row, {
    required Object? replyToMessageId,
    required Object? replyToAuthorId,
    required Object? replyToAuthorTitle,
    required Object? replyToBodyExcerpt,
    required Object? replyToHasAttachments,
  }) {
    expect(row['replyToMessageId'], replyToMessageId);
    expect(row['replyToAuthorId'], replyToAuthorId);
    expect(row['replyToAuthorTitle'], replyToAuthorTitle);
    expect(row['replyToBodyExcerpt'], replyToBodyExcerpt);
    expect(row['replyToHasAttachments'], replyToHasAttachments);
  }

  test(
    'stored reply_to_message_id and list snapshot fields round-trip',
    () async {
      await seedBaseRoom();
      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: 'Parent body for round-trip',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Child reply body',
        replyToMessageId: parent.id,
      );

      final stored = await database.customSelect(
        'SELECT reply_to_message_id FROM public.beacon_room_message '
        'WHERE id = \$1',
        variables: [Variable(reply.id)],
      ).getSingle();
      expect(stored.read<String>('reply_to_message_id'), parent.id);

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expectReplyFields(
        childRow,
        replyToMessageId: parent.id,
        replyToAuthorId: parentAuthorId,
        replyToAuthorTitle: parentAuthorId,
        replyToBodyExcerpt: 'Parent body for round-trip',
        replyToHasAttachments: false,
      );
    },
    skip: skipReason,
  );

  test(
    'parent outside the 50-row window still resolves in list snapshot',
    () async {
      await seedBaseRoom();
      await database.customStatement(
        '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at
) VALUES (
  'Rreplypgparent1', '$beaconId', '$parentAuthorId', 'Off-window parent body',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET body = EXCLUDED.body
''',
      );
      for (var i = 0; i < 50; i++) {
        final id = 'Rreplypgfill${i.toString().padLeft(2, '0')}';
        final created =
            '2026-01-02T12:${i.toString().padLeft(2, '0')}:00Z';
        await database.customStatement(
          '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at
) VALUES (
  '$id', '$beaconId', '$replyAuthorId', 'Filler message $i', '$created'
)
ON CONFLICT (id) DO NOTHING
''',
        );
      }
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Reply to off-window parent',
        replyToMessageId: 'Rreplypgparent1',
      );

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 50,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expectReplyFields(
        childRow,
        replyToMessageId: 'Rreplypgparent1',
        replyToAuthorId: parentAuthorId,
        replyToAuthorTitle: parentAuthorId,
        replyToBodyExcerpt: 'Off-window parent body',
        replyToHasAttachments: false,
      );
      expect(rows.any((r) => r['id'] == 'Rreplypgparent1'), isFalse);
    },
    skip: skipReason,
  );

  test(
    'parent author off the message page still populates replyToAuthorTitle',
    () async {
      await seedBaseRoom();
      await database.customStatement(
        '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at
) VALUES (
  'Rreplypgparent2', '$beaconId', '$parentAuthorId',
  'Parent by off-page author', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET body = EXCLUDED.body
''',
      );
      for (var i = 0; i < 50; i++) {
        final id = 'Rreplypgpage${i.toString().padLeft(2, '0')}';
        final created =
            '2026-01-02T12:${i.toString().padLeft(2, '0')}:00Z';
        await database.customStatement(
          '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, created_at
) VALUES (
  '$id', '$beaconId', '$replyAuthorId', 'Page filler $i', '$created'
)
ON CONFLICT (id) DO NOTHING
''',
        );
      }
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Reply with off-page parent author',
        replyToMessageId: 'Rreplypgparent2',
      );

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 50,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expect(childRow['replyToAuthorTitle'], parentAuthorId);
      expect(
        rows.map((r) => r['authorId']).contains(parentAuthorId),
        isFalse,
      );
    },
    skip: skipReason,
  );

  test(
    'attachment-only parent yields null excerpt and true hasAttachments',
    () async {
      await seedBaseRoom();
      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: '',
      );
      await database.customStatement(
        '''
INSERT INTO public.beacon_room_message_attachment (
  id, message_id, kind, mime, size_bytes
) VALUES ('Areplypgatt01', '${parent.id}', 1, 'image/png', 128)
ON CONFLICT (id) DO NOTHING
''',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Reply to attachment-only parent',
        replyToMessageId: parent.id,
      );

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expectReplyFields(
        childRow,
        replyToMessageId: parent.id,
        replyToAuthorId: parentAuthorId,
        replyToAuthorTitle: parentAuthorId,
        replyToBodyExcerpt: null,
        replyToHasAttachments: true,
      );
    },
    skip: skipReason,
  );

  test(
    'roomMessageTarget returns the same reply snapshot as RoomMessageList',
    () async {
      await seedBaseRoom();
      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: 'Target parity parent',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Target parity reply',
        replyToMessageId: parent.id,
      );

      final listRow = (await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      )).firstWhere((r) => r['id'] == reply.id);
      final targetRow = await room.roomMessageTarget(
        beaconId: beaconId,
        messageId: reply.id,
        viewerUserId: viewerId,
      );

      expect(targetRow, isNotNull);
      for (final key in [
        'replyToMessageId',
        'replyToAuthorId',
        'replyToAuthorTitle',
        'replyToBodyExcerpt',
        'replyToHasAttachments',
      ]) {
        expect(targetRow![key], listRow[key]);
      }
    },
    skip: skipReason,
  );

  test(
    'cross-scope reply pointer does not leak another beacon parent body',
    () async {
      await seedBaseRoom();
      await database.customStatement(
        '''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body
) VALUES (
  'Rreplypgother1', '$otherBeaconId', '$parentAuthorId',
  'Other beacon parent body'
)
ON CONFLICT (id) DO NOTHING
''',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Cross-scope reply attempt',
      );
      await database.customStatement(
        '''
UPDATE public.beacon_room_message
SET reply_to_message_id = 'Rreplypgother1'
WHERE id = '${reply.id}'
''',
      );

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expectReplyFields(
        childRow,
        replyToMessageId: 'Rreplypgother1',
        replyToAuthorId: null,
        replyToAuthorTitle: null,
        replyToBodyExcerpt: null,
        replyToHasAttachments: null,
      );
    },
    skip: skipReason,
  );

  test(
    'parent edit updates child quote excerpt on next read',
    () async {
      await seedBaseRoom();
      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: 'Original parent body',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Reply before parent edit',
        replyToMessageId: parent.id,
      );

      await room.updateMessage(
        messageId: parent.id,
        newBody: 'Edited parent body text',
        mentions: const [],
      );

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expect(childRow['replyToBodyExcerpt'], 'Edited parent body text');
    },
    skip: skipReason,
  );

  test(
    'parent edit notifies only newly added mentions, not reply author',
    () async {
      await seedBaseRoom();
      final dispatch = AttentionDispatchRepository(
        database,
        Logger('room_message_reply_readback_pg_test'),
      );
      final unitOfWork = MutatingUnitOfWork(database);
      final attention = TransactionalAttentionCase(unitOfWork, dispatch);
      final attentionIntents = AttentionIntentCase(
        BeaconRoomNotificationContextRepository(room, database),
        UserRepository(
          Env(environment: Environment.test),
          database,
          _NoopTrustEvidenceRepository(),
          _NoopInviteGenealogyRepository(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconAccessRepository(database),
        FakeUserBlockRepository(),
      );
      final items = CoordinationItemRepository(database);
      final roomCase = BeaconRoomCase(
        room,
        items,
        _PgFakeFactCards(),
        _PgFakeImages(),
        _PgFakeTasks(),
        _PgFakeRemoteStorage(),
        _PgFakePolling(),
        _PgFakeUploadQuota(),
        FakeUserBlockRepository(),
        attentionIntents: attentionIntents,
        attention: attention,
        env: Env(environment: Environment.test),
        logger: Logger('room_message_reply_readback_pg_test'),
      );

      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: 'Parent before mention edit',
      );
      await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Reply to parent before edit',
        replyToMessageId: parent.id,
      );

      Future<int> recipientMentionCount(String recipientId) async {
        final row = await database.customSelect(
          '''
SELECT COUNT(*)::int AS c
FROM public.attention_occurrence_recipient
WHERE account_id = \$1
''',
          variables: [Variable(recipientId)],
        ).getSingle();
        return row.read<int>('c');
      }

      expect(await recipientMentionCount(replyAuthorId), 0);

      await roomCase.editMessage(
        beaconId: beaconId,
        messageId: parent.id,
        userId: parentAuthorId,
        newBody: 'Parent now mentions @newmention',
      );

      expect(await recipientMentionCount(newMentionUserId), 1);
      expect(await recipientMentionCount(replyAuthorId), 0);
    },
    skip: skipReason,
  );

  test(
    'parent delete clears reply pointer and all five read fields',
    () async {
      await seedBaseRoom();
      final parent = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: parentAuthorId,
        body: 'Parent to delete',
      );
      final reply = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: replyAuthorId,
        body: 'Child survives parent delete',
        replyToMessageId: parent.id,
      );

      await database.customStatement(
        'DELETE FROM public.beacon_room_message WHERE id = \'${parent.id}\'',
      );

      final stored = await database.customSelect(
        'SELECT reply_to_message_id FROM public.beacon_room_message '
        'WHERE id = \$1',
        variables: [Variable(reply.id)],
      ).getSingle();
      expect(stored.read<String?>('reply_to_message_id'), isNull);

      final rows = await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: viewerId,
        limit: 10,
      );
      final childRow = rows.firstWhere((r) => r['id'] == reply.id);
      expectReplyFields(
        childRow,
        replyToMessageId: null,
        replyToAuthorId: null,
        replyToAuthorTitle: null,
        replyToBodyExcerpt: null,
        replyToHasAttachments: null,
      );
    },
    skip: skipReason,
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

final class _NoopTrustEvidenceRepository extends Fake
    implements TrustEvidenceRepositoryPort {}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}
