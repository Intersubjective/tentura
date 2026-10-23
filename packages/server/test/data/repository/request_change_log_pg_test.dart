@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/request_change_log_repository.dart';

import '../../support/disposable_pg_target.dart';

/// #528 — a next-step or title edit leaves a `requestEdited` line (kind 8) in
/// General and a paired `requestEdited` activity event; a run of one
/// person's edits of one field stays one line.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_CHANGE_LOG_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_change_log',
  );
  final skipReason = await pgSkipReason(target);

  const authorId = 'Uchangeauth1';
  const helperId = 'Uchangehelp1';
  const beaconId = 'Bchangeline1';
  const postId = 'Bchangepost1';

  group('RequestChangeLogRepository.recordEdit (#528)', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late RequestChangeLogRepository log;

    Future<List<Map<String, Object?>>> editLines(String id) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT id, author_id, system_payload::text '
          'FROM public.beacon_room_message '
          'WHERE beacon_id = @id AND system_message_kind = @kind '
          'ORDER BY created_at, id',
        ),
        parameters: {
          'id': id,
          'kind': BeaconRoomSystemMessageKind.requestEdited,
        },
      );
      return [
        for (final r in rows)
          {
            'id': r[0],
            'author': r[1],
            'payload': jsonDecode(r[2]! as String),
          },
      ];
    }

    Future<List<Map<String, Object?>>> editEvents(String id) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT actor_id, source_message_id, visibility, diff::text '
          'FROM public.beacon_activity_event '
          'WHERE beacon_id = @id AND type = @type '
          'ORDER BY created_at, id',
        ),
        parameters: {
          'id': id,
          'type': BeaconActivityEventTypeBits.requestEdited,
        },
      );
      return [
        for (final r in rows)
          {
            'actor': r[0],
            'source': r[1],
            'visibility': r[2],
            'diff': jsonDecode(r[3]! as String),
          },
      ];
    }

    Future<void> insertBeacon(String id, {required int kind}) {
      final isPost = kind == 1;
      final title = isPost ? '' : 'Moving day';
      final description = isPost ? '' : 'desc';
      return writer.execute(
        'INSERT INTO public.beacon (id, user_id, title, description, '
        'status, kind, is_discoverable, published_at, created_at, '
        "updated_at) VALUES ('$id', '$authorId', '$title', '$description', "
        "0, $kind, ${!isPost}, '2026-01-01T00:00:00Z', "
        "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
      );
    }

    Future<void> chat(String id, String userId) => writer.execute(
      'INSERT INTO public.beacon_room_message (beacon_id, author_id, body) '
      "VALUES ('$id', '$userId', 'hello')",
    );

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = TenturaDb(target.databaseEnv);
      log = RequestChangeLogRepository(db);
    });

    tearDownAll(() async {
      if (skipReason != null) return;
      await db.close();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != null) return;
      await writer.execute(
        'TRUNCATE TABLE public.beacon_activity_event, '
        'public.beacon_room_message, public.beacon, public."user" CASCADE',
      );
      for (final (id, name) in [(authorId, 'Author'), (helperId, 'Nina')]) {
        await writer.execute(
          'INSERT INTO public."user" (id, display_name, public_key) '
          "VALUES ('$id', '$name', 'key-$id')",
        );
      }
      await insertBeacon(beaconId, kind: 0);
    });

    test('a next-step edit writes one line and its linked event', () async {
      await log.recordEdit(
        beaconId: beaconId,
        actorId: authorId,
        field: RequestEditField.nextStep,
        from: '',
        to: 'Nina: van 9:45',
      );
      final lines = await editLines(beaconId);
      expect(lines, hasLength(1));
      expect(lines.single['author'], authorId);
      expect(lines.single['payload'], {
        'version': 1,
        'field': 'nextStep',
        'from': '',
        'to': 'Nina: van 9:45',
      });
      final events = await editEvents(beaconId);
      expect(events, hasLength(1));
      expect(events.single['actor'], authorId);
      expect(events.single['source'], lines.single['id']);
      expect(
        events.single['visibility'],
        BeaconActivityEventVisibilityBits.room,
      );
      expect(events.single['diff'], {
        'field': 'nextStep',
        'from': '',
        'to': 'Nina: van 9:45',
      });
    });

    test(
      "a run of one person's edits stays one line; the log keeps all",
      () async {
        for (final (from, to) in [('', 'a'), ('a', 'b'), ('b', 'c')]) {
          await log.recordEdit(
            beaconId: beaconId,
            actorId: authorId,
            field: RequestEditField.nextStep,
            from: from,
            to: to,
          );
        }
        final lines = await editLines(beaconId);
        expect(lines, hasLength(1));
        final payload = lines.single['payload']! as Map;
        expect(payload['from'], '');
        expect(payload['to'], 'c');
        expect(payload['edits'], 3);
        final events = await editEvents(beaconId);
        expect(events, hasLength(3));
        expect(events.map((e) => e['source']).toSet(), {lines.single['id']});
      },
    );

    test('another person, another field, a chat message or an old line '
        'starts a new line', () async {
      Future<void> edit(String actor, String field, String to) =>
          log.recordEdit(
            beaconId: beaconId,
            actorId: actor,
            field: field,
            from: 'x',
            to: to,
          );
      await edit(authorId, RequestEditField.nextStep, '1');
      await edit(helperId, RequestEditField.nextStep, '2');
      await edit(helperId, RequestEditField.title, '3');
      await chat(beaconId, authorId);
      await edit(helperId, RequestEditField.title, '4');
      // Older than the coalesce window.
      await writer.execute(
        'UPDATE public.beacon_room_message '
        "SET created_at = created_at - interval '11 minutes' "
        "WHERE beacon_id = '$beaconId' AND system_message_kind = "
        '${BeaconRoomSystemMessageKind.requestEdited}',
      );
      await edit(helperId, RequestEditField.title, '5');
      final lines = await editLines(beaconId);
      expect(
        [for (final l in lines) (l['payload']! as Map)['to']],
        ['1', '2', '3', '4', '5'],
      );
    });

    test('an unchanged value or a Post writes nothing', () async {
      await insertBeacon(postId, kind: 1);
      await log.recordEdit(
        beaconId: beaconId,
        actorId: authorId,
        field: RequestEditField.title,
        from: 'same',
        to: 'same',
      );
      await log.recordEdit(
        beaconId: postId,
        actorId: authorId,
        field: RequestEditField.nextStep,
        from: '',
        to: 'x',
      );
      expect(await editLines(beaconId), isEmpty);
      expect(await editLines(postId), isEmpty);
      expect(await editEvents(postId), isEmpty);
    });
  }, skip: skipReason ?? false);
}
