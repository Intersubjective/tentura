@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/coordination_item_repository.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon threads PG test';

  group('CoordinationItemRepository.listThreads — disposable Postgres', () {
    late Connection writer;
    late TenturaDb db;
    late CoordinationItemRepository items;
    late BeaconRoomRepository room;

    const beaconId = 'Bthpg00000001';
    const memberId = 'Uthpgmember01';
    const targetId = 'Uthpgtarget01';
    const otherId = 'Uthpgother001';

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
      items = CoordinationItemRepository(db);
      room = BeaconRoomRepository(db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_room_message_attachment WHERE message_id LIKE 'Rthpg%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE id LIKE 'Rthpg%' OR beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_seen WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_fact_card WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.polling_variant WHERE polling_id LIKE 'Pthpg%'",
      );
      await writer.execute(
        "DELETE FROM public.polling WHERE id LIKE 'Pthpg%'",
      );
      await writer.execute(
        "DELETE FROM public.coordination_item WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id LIKE 'Uthpg%'",
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> seedBaseUsersAndBeacon() async {
      for (final entry in <(String, int)>[
        (memberId, 1),
        (targetId, 2),
        (otherId, 3),
      ]) {
        await writer.execute(
          Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
          parameters: {
            'id': entry.$1,
            'publicKey': pgTestPublicKey('thpg', entry.$2),
          },
        );
      }
      await writer.execute(
        '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$memberId', 'Threads PG', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
      await writer.execute(
        '''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES ('Pthpgmember01', '$beaconId', '$memberId', 0, 0, 3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''',
      );
    }

    Future<void> insertItem({
      required String id,
      required int kind,
      required String creatorId,
      bool published = true,
      int status = coordinationItemStatusOpen,
      String? targetPersonId,
      String title = 'Item',
    }) async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, @title, '', @creatorId, @targetPersonId,
  @published, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z',
  CASE WHEN @published THEN '2026-01-02T00:00:00Z'::timestamptz ELSE NULL END,
  0, 0
)
ON CONFLICT (id) DO UPDATE SET
  published = EXCLUDED.published,
  status = EXCLUDED.status,
  target_person_id = EXCLUDED.target_person_id
'''),
        parameters: {
          'id': id,
          'beaconId': beaconId,
          'kind': kind,
          'status': status,
          'title': title,
          'creatorId': creatorId,
          'targetPersonId': targetPersonId,
          'published': published,
        },
      );
    }

    Future<void> insertMessage({
      required String id,
      required String authorId,
      String body = '',
      String? threadItemId,
      int? semanticMarker,
      String? linkedItemId,
      int? linkedEventKind,
      String? linkedPollingId,
      String? linkedFactCardId,
      Map<String, Object?>? systemPayload,
      DateTime? createdAt,
    }) async {
      final at = (createdAt ?? DateTime.utc(2026, 1, 3)).toIso8601String();
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, thread_item_id, semantic_marker,
  linked_item_id, linked_event_kind, linked_polling_id, linked_fact_card_id,
  system_payload, created_at
) VALUES (
  @id, @beaconId, @authorId, @body, @threadItemId, @semanticMarker,
  @linkedItemId, @linkedEventKind, @linkedPollingId, @linkedFactCardId,
  CAST(@systemPayload AS jsonb), @createdAt::timestamptz
)
ON CONFLICT (id) DO UPDATE SET
  body = EXCLUDED.body,
  semantic_marker = EXCLUDED.semantic_marker,
  linked_item_id = EXCLUDED.linked_item_id,
  linked_event_kind = EXCLUDED.linked_event_kind,
  linked_polling_id = EXCLUDED.linked_polling_id,
  linked_fact_card_id = EXCLUDED.linked_fact_card_id,
  system_payload = EXCLUDED.system_payload,
  created_at = EXCLUDED.created_at
'''),
        parameters: {
          'id': id,
          'beaconId': beaconId,
          'authorId': authorId,
          'body': body,
          'threadItemId': threadItemId,
          'semanticMarker': semanticMarker,
          'linkedItemId': linkedItemId,
          'linkedEventKind': linkedEventKind,
          'linkedPollingId': linkedPollingId,
          'linkedFactCardId': linkedFactCardId,
          'systemPayload': systemPayload == null ? null : _json(systemPayload),
          'createdAt': at,
        },
      );
    }

    BeaconThreadRecord? rowFor(
      List<BeaconThreadRecord> rows,
      String threadId,
    ) {
      for (final row in rows) {
        if (row.threadId == threadId) {
          return row;
        }
      }
      return null;
    }

    test(
      'disposable target uses an isolated database name',
      () {
        expect(target.databaseName, startsWith('tentura_test_'));
        expect(target.databaseName, isNot('postgres'));
      },
      skip: skipReason,
    );

    test(
      'room member gets General exactly once plus eligible items',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgaskpub01',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        expect(rows.where((r) => r.threadId == 'general'), hasLength(1));
        expect(rows.any((r) => r.threadId == 'Ithpgaskpub01'), isTrue);
      },
      skip: skipReason,
    );

    test(
      'item-only participant has no General row',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgaskpub02',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: targetId,
          includeGeneral: false,
          itemParticipantsOnly: true,
          excerptCharacters: 140,
        );

        expect(rows.every((r) => r.threadId != 'general'), isTrue);
        expect(rows.single.threadId, 'Ithpgaskpub02');
      },
      skip: skipReason,
    );

    test(
      'item-only participant with no eligible items returns empty list',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgaskpub03',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: otherId,
          includeGeneral: false,
          itemParticipantsOnly: true,
          excerptCharacters: 140,
        );

        expect(rows, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'published zero-message item appears',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgaskzero1',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
          title: 'Zero messages',
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        final itemRow = rowFor(rows, 'Ithpgaskzero1');
        expect(itemRow, isNotNull);
        expect(itemRow!.messageCount, 0);
        expect(itemRow.lastMessagePreview, isNull);
      },
      skip: skipReason,
    );

    test(
      'viewer draft appears and someone else draft is absent',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgdraftown',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          published: false,
          title: 'Own draft',
        );
        await insertItem(
          id: 'Ithpgdraftoth',
          kind: coordinationItemKindAsk,
          creatorId: otherId,
          published: false,
          title: 'Other draft',
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        expect(rowFor(rows, 'Ithpgdraftown'), isNotNull);
        expect(rowFor(rows, 'Ithpgdraftoth'), isNull);
      },
      skip: skipReason,
    );

    test(
      'closed item still appears',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgclosed1',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
          status: coordinationItemStatusResolved,
          title: 'Closed ask',
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        expect(rowFor(rows, 'Ithpgclosed1'), isNotNull);
      },
      skip: skipReason,
    );

    test(
      'General unread includes plan-updated messages',
      () async {
        await seedBaseUsersAndBeacon();
        await insertMessage(
          id: 'Rthpgplan001',
          authorId: otherId,
          semanticMarker: BeaconRoomSemanticMarker.updatePlan,
          createdAt: DateTime.utc(2026, 1, 4),
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        final general = rowFor(rows, 'general')!;
        expect(general.messageCount, 1);
        expect(general.unreadCount, 1);
      },
      skip: skipReason,
    );

    test(
      'viewers own General message is not unread and watermark applies',
      () async {
        await seedBaseUsersAndBeacon();
        await insertMessage(
          id: 'Rthpgown001',
          authorId: memberId,
          body: 'mine',
          createdAt: DateTime.utc(2026, 1, 4, 1),
        );
        await insertMessage(
          id: 'Rthpgother01',
          authorId: otherId,
          body: 'theirs',
          createdAt: DateTime.utc(2026, 1, 4, 2),
        );
        await writer.execute('''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES ('$memberId', '$beaconId', NULL, '2026-01-04T01:30:00Z')
ON CONFLICT DO NOTHING
''');

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        final general = rowFor(rows, 'general')!;
        expect(general.messageCount, 2);
        expect(general.unreadCount, 1);
        expect(general.lastSeenAt, DateTime.utc(2026, 1, 4, 1, 30));
      },
      skip: skipReason,
    );

    test(
      'row-level lastSeenAt is returned for General and semantic rows',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgseenitem',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
        );
        await writer.execute('''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES
  ('$memberId', '$beaconId', NULL, '2026-01-04T10:00:00Z'),
  ('$memberId', '$beaconId', 'Ithpgseenitem', '2026-01-04T11:00:00Z')
ON CONFLICT DO NOTHING
''');

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );

        expect(
          rowFor(rows, 'general')!.lastSeenAt,
          DateTime.utc(2026, 1, 4, 10),
        );
        expect(
          rowFor(rows, 'Ithpgseenitem')!.lastSeenAt,
          DateTime.utc(2026, 1, 4, 11),
        );
      },
      skip: skipReason,
    );

    test(
      'General unread matches countRoomMessagesAfter',
      () async {
        await seedBaseUsersAndBeacon();
        final seenAt = DateTime.utc(2026, 1, 4, 12);
        await writer.execute('''
INSERT INTO public.beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES ('$memberId', '$beaconId', NULL, '${seenAt.toIso8601String()}')
ON CONFLICT DO NOTHING
''');
        await insertMessage(
          id: 'Rthpgparity1',
          authorId: otherId,
          body: 'before',
          createdAt: DateTime.utc(2026, 1, 4, 11),
        );
        await insertMessage(
          id: 'Rthpgparity2',
          authorId: otherId,
          body: 'after',
          createdAt: DateTime.utc(2026, 1, 4, 13),
        );
        await insertMessage(
          id: 'Rthpgparity3',
          authorId: memberId,
          body: 'self',
          createdAt: DateTime.utc(2026, 1, 4, 14),
        );

        final rows = await items.listThreads(
          beaconId: beaconId,
          viewerUserId: memberId,
          includeGeneral: true,
          itemParticipantsOnly: false,
          excerptCharacters: 140,
        );
        final expected = await room.countRoomMessagesAfter(
          beaconId: beaconId,
          after: seenAt,
          excludeAuthorId: memberId,
        );

        expect(rowFor(rows, 'general')!.unreadCount, expected);
        expect(expected, 1);
      },
      skip: skipReason,
    );

    test(
      'preview kinds 0-9 and coordination lifecycle without marker',
      () async {
        await seedBaseUsersAndBeacon();
        await insertItem(
          id: 'Ithpgprev000',
          kind: coordinationItemKindAsk,
          creatorId: memberId,
          targetPersonId: targetId,
          title: 'Preview host',
        );
        await writer.execute('''
INSERT INTO public.beacon_fact_card (
  id, beacon_id, pinned_by, fact_text, visibility, created_at, updated_at
) VALUES ('Fthpgfact001', '$beaconId', '$memberId', 'Pinned fact', 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
        await writer.execute('''
INSERT INTO public.polling (
  id, author_id, question, poll_type, is_anonymous, allow_revote, created_at, updated_at
) VALUES ('Pthpgpoll001', '$memberId', 'Lunch?', 'single', true, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''');

        final previewCases = <({
          String messageId,
          String? threadItemId,
          int expectedKind,
          String body,
          int? marker,
          String? linkedItemId,
          int? linkedEventKind,
          String? pollId,
          String? factId,
          Map<String, Object?>? payload,
          bool withAttachment,
        })>[
          (
            messageId: 'Rthpgprev00',
            threadItemId: 'Ithpgprev000',
            expectedKind: ThreadMessagePreviewKind.text,
            body: 'hello preview',
            marker: null,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev01',
            threadItemId: 'Ithpgprev000',
            expectedKind: ThreadMessagePreviewKind.attachment,
            body: '',
            marker: null,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: true,
          ),
          (
            messageId: 'Rthpgprev02',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.planUpdated,
            body: '',
            marker: BeaconRoomSemanticMarker.updatePlan,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev03',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.factPinned,
            body: '',
            marker: BeaconRoomSemanticMarker.pinFactPublic,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: 'Fthpgfact001',
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev04',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.participantStatus,
            body: '',
            marker: BeaconRoomSemanticMarker.participantStatusChanged,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev05',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.coordination,
            body: '',
            marker: BeaconRoomSemanticMarker.blocker,
            linkedItemId: 'Ithpgprev000',
            linkedEventKind: coordinationEventKindCreated,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev06',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.needInfo,
            body: '',
            marker: BeaconRoomSemanticMarker.needInfo,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev07',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.done,
            body: '',
            marker: BeaconRoomSemanticMarker.done,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev08',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.poll,
            body: '',
            marker: BeaconRoomSemanticMarker.poll,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: 'Pthpgpoll001',
            factId: null,
            payload: null,
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev09',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.join,
            body: '',
            marker: BeaconRoomSemanticMarker.participantJoined,
            linkedItemId: null,
            linkedEventKind: null,
            pollId: null,
            factId: null,
            payload: {
              'joinedUserId': targetId,
              'admissionReason': BeaconRoomAdmissionReason.accept,
            },
            withAttachment: false,
          ),
          (
            messageId: 'Rthpgprev10',
            threadItemId: null,
            expectedKind: ThreadMessagePreviewKind.coordination,
            body: '',
            marker: null,
            linkedItemId: 'Ithpgprev000',
            linkedEventKind: coordinationEventKindCreated,
            pollId: null,
            factId: null,
            payload: null,
            withAttachment: false,
          ),
        ];

        for (final c in previewCases) {
          await writer.execute(
            "DELETE FROM public.beacon_room_message_attachment "
            "WHERE message_id LIKE 'Rthpgprev%'",
          );
          await writer.execute(
            "DELETE FROM public.beacon_room_message WHERE id LIKE 'Rthpgprev%'",
          );
          await insertMessage(
            id: c.messageId,
            authorId: memberId,
            body: c.body,
            threadItemId: c.threadItemId,
            semanticMarker: c.marker,
            linkedItemId: c.linkedItemId,
            linkedEventKind: c.linkedEventKind,
            linkedPollingId: c.pollId,
            linkedFactCardId: c.factId,
            systemPayload: c.payload,
          );
          if (c.withAttachment) {
            await writer.execute(r'''
INSERT INTO public.beacon_room_message_attachment (
  id, message_id, kind, mime, size_bytes
) VALUES ('Athpgprev01', 'Rthpgprev01', 1, 'image/png', 1)
ON CONFLICT (id) DO NOTHING
''');
          }

          final rows = await items.listThreads(
            beaconId: beaconId,
            viewerUserId: memberId,
            includeGeneral: true,
            itemParticipantsOnly: false,
            excerptCharacters: 140,
          );
          final host =
              c.threadItemId == null ? rowFor(rows, 'general') : rowFor(rows, c.threadItemId!);
          final preview = host?.lastMessagePreview;
          expect(preview?.kind, c.expectedKind, reason: 'kind for ${c.messageId}');

          if (c.expectedKind == ThreadMessagePreviewKind.text) {
            expect(preview!.excerpt, 'hello preview');
          }
          if (c.expectedKind == ThreadMessagePreviewKind.join) {
            expect(preview!.admissionReason, BeaconRoomAdmissionReason.accept);
            expect(preview.joinedUserId, targetId);
            expect(preview.excerpt, isNull);
          }
          if (c.expectedKind == ThreadMessagePreviewKind.coordination &&
              c.marker == null) {
            expect(preview!.linkedItemId, 'Ithpgprev000');
            expect(preview.linkedEventKind, coordinationEventKindCreated);
          }
          if (c.expectedKind == ThreadMessagePreviewKind.poll) {
            expect(preview!.pollTitle, 'Lunch?');
          }
          if (c.expectedKind == ThreadMessagePreviewKind.factPinned) {
            expect(preview!.factTitle, 'Pinned fact');
          }
        }
      },
      skip: skipReason,
    );
  });
}

String _json(Map<String, Object?> value) {
  final buffer = StringBuffer('{');
  var first = true;
  for (final entry in value.entries) {
    if (!first) {
      buffer.write(',');
    }
    first = false;
    buffer
      ..write('"')
      ..write(entry.key)
      ..write('":');
    final v = entry.value;
    if (v is String) {
      buffer
        ..write('"')
        ..write(v)
        ..write('"');
    } else {
      buffer.write(v);
    }
  }
  buffer.write('}');
  return buffer.toString();
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

final class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_BEACON_THREADS_PG_TEST_DB'] ??
        'tentura_test_bthreads_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_BEACON_THREADS_PG_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE $databaseName');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
