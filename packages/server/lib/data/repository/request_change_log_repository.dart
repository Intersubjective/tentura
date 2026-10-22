import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/port/request_change_log_port.dart';

import '../database/tentura_db.dart';

/// Request edit lines (#528) — Postgres, in plain SQL.
@LazySingleton(as: RequestChangeLogPort)
class RequestChangeLogRepository implements RequestChangeLogPort {
  const RequestChangeLogRepository(this._db);

  final TenturaDb _db;

  @override
  Future<void> recordEdit({
    required String beaconId,
    required String actorId,
    required String field,
    required String from,
    required String to,
  }) async {
    if (!RequestEditField.all.contains(field)) {
      throw ArgumentError.value(field, 'field', 'not a RequestEditField');
    }
    if (from == to) return;
    await _db.withMutatingUser(actorId, () async {
      final lineId =
          await _coalesceIntoTail(
            beaconId: beaconId,
            actorId: actorId,
            field: field,
            to: to,
          ) ??
          await _insertLine(
            beaconId: beaconId,
            actorId: actorId,
            field: field,
            from: from,
            to: to,
          );
      // A Post (or a missing Request) gets no line and no log entry.
      if (lineId == null) return;
      await _db.customStatement(
        r'''
INSERT INTO public.beacon_activity_event
  (beacon_id, visibility, type, actor_id, source_message_id, diff)
VALUES ($1, $2, $3, $4, $5, $6::text::jsonb)
''',
        [
          beaconId,
          BeaconActivityEventVisibilityBits.room,
          BeaconActivityEventTypeBits.requestEdited,
          actorId,
          lineId,
          jsonEncode({'field': field, 'from': from, 'to': to}),
        ],
      );
    });
  }

  /// The id of the tail line that took [to], or null when the newest General
  /// message is not this person's fresh line for [field].
  Future<String?> _coalesceIntoTail({
    required String beaconId,
    required String actorId,
    required String field,
    required String to,
  }) async {
    final tail = await _db
        .customSelect(
          r'''
SELECT id, author_id, system_message_kind,
       system_payload::text AS system_payload,
       (now() - created_at) < make_interval(secs => $2) AS fresh
FROM public.beacon_room_message
WHERE beacon_id = $1 AND thread_item_id IS NULL
ORDER BY created_at DESC, id DESC
LIMIT 1
''',
          variables: [
            Variable<String>(beaconId),
            Variable<double>(
              kRequestEditLineCoalesceWindow.inSeconds.toDouble(),
            ),
          ],
        )
        .getSingleOrNull();
    if (tail == null ||
        tail.readNullable<int>('system_message_kind') !=
            BeaconRoomSystemMessageKind.requestEdited ||
        tail.readNullable<String>('author_id') != actorId ||
        !(tail.readNullable<bool>('fresh') ?? false)) {
      return null;
    }
    final raw = tail.readNullable<String>('system_payload');
    final payload = raw == null ? null : jsonDecode(raw);
    if (payload is! Map || payload['field'] != field) return null;
    final id = tail.read<String>('id');
    final edits = payload['edits'];
    await _db.customStatement(
      r'''
UPDATE public.beacon_room_message
SET system_payload = $2::text::jsonb, created_at = now()
WHERE id = $1
''',
      [
        id,
        jsonEncode({
          ...payload.cast<String, Object?>(),
          'to': to,
          'edits': (edits is num ? edits.toInt() : 1) + 1,
        }),
      ],
    );
    return id;
  }

  Future<String?> _insertLine({
    required String beaconId,
    required String actorId,
    required String field,
    required String from,
    required String to,
  }) async {
    final row = await _db
        .customSelect(
          r'''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, system_message_kind, system_payload)
SELECT b.id, $2, '', $3, $4::text::jsonb
FROM public.beacon b
WHERE b.id = $1 AND b.kind = 0
RETURNING id
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(actorId),
            const Variable<int>(BeaconRoomSystemMessageKind.requestEdited),
            Variable<String>(
              jsonEncode({
                'version': 1,
                'field': field,
                'from': from,
                'to': to,
              }),
            ),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }
}
