import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';

@LazySingleton(as: BeaconFactCardRepositoryPort)
class BeaconFactCardRepository implements BeaconFactCardRepositoryPort {
  BeaconFactCardRepository(this._db, this._room);

  final TenturaDb _db;

  final BeaconRoomRepositoryPort _room;

  /// Plan §8.2 / §14.3: one SELECT for status, room use and content read.
  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _db.customSelect(
      '''
SELECT
  b.status::integer AS beacon_status,
  (
    b.user_id = \$2::text
    OR EXISTS (
      SELECT 1 FROM public.beacon_steward s
      WHERE s.beacon_id = b.id AND s.user_id = \$2::text
    )
    OR EXISTS (
      SELECT 1 FROM public.beacon_participant p
      WHERE p.beacon_id = b.id
        AND p.user_id = \$2::text
        AND p.room_access = ${RoomAccessBits.admitted}
    )
  ) AS can_use_room,
  public.beacon_can_read_content(b.id, \$2::text) AS can_read_content
FROM public.beacon b
WHERE b.id = \$1::text
''',
      variables: [Variable<String>(beaconId), Variable<String>(userId)],
    ).getSingleOrNull();
    if (row == null) {
      return const BeaconFactRoomAccess(
        beaconStatus: 0,
        canUseRoom: false,
        canReadContent: false,
        exists: false,
      );
    }
    return BeaconFactRoomAccess(
      beaconStatus: row.read<int>('beacon_status'),
      canUseRoom: row.read<bool>('can_use_room'),
      canReadContent: row.read<bool>('can_read_content'),
      exists: true,
    );
  }

  /// Plan §8.4 "Fact list": non-removed facts with pinner and last editor
  /// titles joined; room-only facts only when [includeRoomOnly]. No LIMIT.
  @override
  Future<List<BeaconFactCardEntity>> listForBeacon({
    required String beaconId,
    required bool includeRoomOnly,
  }) async {
    final rows = await _db.customSelect(
      '''
SELECT
  f.id, f.beacon_id, f.fact_text, f.visibility::integer AS visibility,
  f.pinned_by, f.source_message_id, f.status::integer AS status,
  f.created_at, f.updated_at, f.revision_seq, f.last_edited_by,
  f.last_edited_at, f.other_editor_count, f.history_truncated,
  pu.display_name AS pinned_by_title,
  eu.display_name AS last_edited_by_title
FROM public.beacon_fact_card f
LEFT JOIN public."user" pu ON pu.id = f.pinned_by
LEFT JOIN public."user" eu ON eu.id = f.last_edited_by
WHERE f.beacon_id = \$1::text
  AND f.status <> ${BeaconFactCardStatusBits.removed}
  AND (\$2::boolean OR f.visibility <> ${BeaconFactCardVisibilityBits.room})
ORDER BY f.created_at, f.id
''',
      variables: [Variable<String>(beaconId), Variable<bool>(includeRoomOnly)],
    ).get();
    return [
      for (final row in rows)
        BeaconFactCardEntity(
          id: row.read<String>('id'),
          beaconId: row.read<String>('beacon_id'),
          factText: row.read<String>('fact_text'),
          visibility: row.read<int>('visibility'),
          pinnedBy: row.read<String>('pinned_by'),
          createdAt: _readTimestamp(row, 'created_at'),
          sourceMessageId: row.readNullable<String>('source_message_id'),
          status: row.read<int>('status'),
          updatedAt: _readNullableTimestamp(row, 'updated_at'),
          revisionSeq: row.read<int>('revision_seq'),
          lastEditedBy: row.readNullable<String>('last_edited_by'),
          lastEditedByTitle: row.readNullable<String>('last_edited_by_title'),
          lastEditedAt: _readNullableTimestamp(row, 'last_edited_at'),
          otherEditorCount: row.read<int>('other_editor_count'),
          historyTruncated: row.read<bool>('history_truncated'),
          pinnedByTitle: row.readNullable<String>('pinned_by_title') ?? '',
        ),
    ];
  }

  /// Latest active public fact line for inbox / forward strips.
  Future<String?> latestPublicFactSnippet(String beaconId) async {
    final rows = await _db.managers.beaconFactCards
        .filter(
          (r) =>
              r.beaconId.id(beaconId) &
              r.visibility.equals(BeaconFactCardVisibilityBits.public) &
              r.status.equals(BeaconFactCardStatusBits.active),
        )
        .get();
    if (rows.isEmpty) return null;
    var best = rows.first;
    for (final r in rows.skip(1)) {
      if (r.createdAt.dateTime.isAfter(best.createdAt.dateTime)) {
        best = r;
      }
    }
    final t = best.factText.trim();
    if (t.length > 160) {
      return '${t.substring(0, 157)}…';
    }
    return t;
  }

  /// Plan §8.3 "Pin" / §14.3: one `ON CONFLICT` CTE writes the fact, its
  /// seq-1 revision, the source link, the pin line and the `factPinned`
  /// event. Source ownership is an EXISTS inside the CTE. `DO NOTHING` on the
  /// live-source unique index costs one extra read for the existing id.
  @override
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) =>
      _db.withMutatingUser(pinnedBy, () async {
        final isPublic = visibility == BeaconFactCardVisibilityBits.public;
        final row = await _db.customSelect(
          '''
WITH src AS (
  SELECT (
    \$5::text IS NULL OR EXISTS (
      SELECT 1 FROM public.beacon_room_message m
      WHERE m.id = \$5::text AND m.beacon_id = \$1::text
    )
  ) AS ok
),
fact AS (
  INSERT INTO public.beacon_fact_card
    (id, beacon_id, fact_text, visibility, pinned_by, source_message_id,
     status, updated_at)
  SELECT \$6::text, \$1::text, \$2::text, \$3::smallint, \$4::text, \$5::text,
         ${BeaconFactCardStatusBits.active}, now()
  FROM src
  WHERE src.ok
  ON CONFLICT (source_message_id)
    WHERE status IN (0, 1) AND source_message_id IS NOT NULL
  DO NOTHING
  RETURNING id, beacon_id, fact_text, visibility::integer AS visibility,
            pinned_by, source_message_id, status::integer AS status,
            created_at, updated_at
),
revision AS (
  INSERT INTO public.beacon_fact_card_revision
    (id, fact_card_id, seq, fact_text, actor_id, kind)
  SELECT \$7::text, f.id, 1, f.fact_text, f.pinned_by,
         ${BeaconFactCardRevisionKindBits.created}
  FROM fact f
),
link AS (
  UPDATE public.beacon_room_message m
  SET linked_fact_card_id = f.id
  FROM fact f
  WHERE m.id = f.source_message_id
),
line AS (
  INSERT INTO public.beacon_room_message
    (id, beacon_id, author_id, body, semantic_marker, system_payload,
     mention_spans)
  SELECT \$8::text, f.beacon_id, f.pinned_by, '', \$10::smallint,
         jsonb_strip_nulls(jsonb_build_object(
           'factCardId', f.id,
           'factText', f.fact_text,
           'sourceMessageId', f.source_message_id
         )),
         '[]'::jsonb
  FROM fact f
  RETURNING id
),
event AS (
  INSERT INTO public.beacon_activity_event
    (id, beacon_id, visibility, type, actor_id, source_message_id, diff,
     fact_card_id)
  SELECT \$9::text, f.beacon_id, \$11::smallint,
         ${BeaconActivityEventTypeBits.factPinned}, f.pinned_by,
         COALESCE(f.source_message_id, l.id),
         jsonb_build_object('factCardId', f.id, 'factText', f.fact_text),
         f.id
  FROM fact f CROSS JOIN line l
)
SELECT src.ok AS source_ok, f.*
FROM src LEFT JOIN fact f ON true
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(factText.trim()),
            Variable<int>(visibility),
            Variable<String>(pinnedBy),
            Variable<String>(sourceMessageId),
            Variable<String>(generateId('F')),
            Variable<String>(generateId('FR')),
            Variable<String>(generateId('R')),
            Variable<String>(BeaconActivityEventEntity.newId),
            Variable<int>(
              isPublic
                  ? BeaconRoomSemanticMarker.pinFactPublic
                  : BeaconRoomSemanticMarker.pinFactPrivate,
            ),
            Variable<int>(
              isPublic
                  ? BeaconActivityEventVisibilityBits.public
                  : BeaconActivityEventVisibilityBits.room,
            ),
          ],
        ).getSingle();
        if (!row.read<bool>('source_ok')) {
          throw IdNotFoundException(
            description: 'Source message [$sourceMessageId]',
          );
        }
        final id = row.readNullable<String>('id');
        if (id == null) {
          final existing = await _db.customSelect(
            r'''
SELECT id FROM public.beacon_fact_card
WHERE source_message_id = $1::text AND status IN (0, 1)
''',
            variables: [Variable<String>(sourceMessageId)],
          ).getSingle();
          throw BeaconFactCardAlreadyPinnedException(
            existingFactCardId: existing.read<String>('id'),
          );
        }
        return BeaconFactCardEntity(
          id: id,
          beaconId: row.read<String>('beacon_id'),
          factText: row.read<String>('fact_text'),
          visibility: row.read<int>('visibility'),
          pinnedBy: row.read<String>('pinned_by'),
          createdAt: _readTimestamp(row, 'created_at'),
          sourceMessageId: row.readNullable<String>('source_message_id'),
          status: row.read<int>('status'),
          updatedAt: _readNullableTimestamp(row, 'updated_at'),
        );
      });

  Future<void> setVisibility({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int visibility,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        if (visibility != BeaconFactCardVisibilityBits.public &&
            visibility != BeaconFactCardVisibilityBits.room) {
          throw ArgumentError('visibility');
        }
        final rows = await _db.managers.beaconFactCards.filter(
          (e) =>
              e.id.equals(factCardId) &
              e.beaconId.id(beaconId),
        ).get();
        final row = rows.singleOrNull;
        if (row == null) {
          throw IdNotFoundException(description: 'Fact card [$factCardId]');
        }
        final prevVis = row.visibility;
        await _db.managers.beaconFactCards
            .filter(
              (e) =>
                  e.id.equals(factCardId) &
                  e.beaconId.id(beaconId),
            )
            .update(
              (u) => u(
                    visibility: Value(visibility),
                    updatedAt: Value(PgDateTime(DateTime.timestamp())),
                  ),
            );
        await _room.insertActivityEvent(
          beaconId: beaconId,
          visibility: visibility == BeaconFactCardVisibilityBits.public
              ? BeaconActivityEventVisibilityBits.public
              : BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.factVisibilityChanged,
          actorId: actorUserId,
          sourceMessageId: row.sourceMessageId,
          diff: <String, Object?>{
            'factCardId': row.id,
            'previousVisibility': prevVis,
            'visibility': visibility,
          },
        );
      });

  Future<void> correct({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        final t = newText.trim();
        if (t.isEmpty) {
          throw ArgumentError('newText');
        }
        await _db.managers.beaconFactCards
            .filter(
              (e) =>
                  e.id.equals(factCardId) &
                  e.beaconId.id(beaconId),
            )
            .update(
              (u) => u(
                factText: Value(t),
                status: const Value(BeaconFactCardStatusBits.corrected),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconRoomMessages
            .filter((m) => m.linkedFactCardId.equals(factCardId))
            .update(
              (u) => u(linkedFactCardId: const Value.absent()),
            );
        await _db.managers.beaconFactCards.filter(
          (e) =>
              e.id.equals(factCardId) &
              e.beaconId.id(beaconId),
        ).update(
          (u) => u(
                status: const Value(BeaconFactCardStatusBits.removed),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  /// Plan §8.4 / §14.3: one keyset read over the fact's revisions and its
  /// fact events (types 2, 14, 20). `entry_key` breaks `created_at` ties:
  /// `'r' || lpad(seq, 10)` for revisions, `'e' || id` for events.
  @override
  Future<List<BeaconFactHistoryEntry>> history({
    required String factCardId,
    ({DateTime createdAt, String entryKey})? before,
    int limit = kFactHistoryPageSize,
  }) async {
    final variables = <Variable>[
      Variable<String>(factCardId),
      Variable<int>(limit + 1),
    ];
    var cursorSql = '';
    if (before != null) {
      cursorSql = r'''
WHERE (h.created_at, h.entry_key) < ($3::timestamptz, $4::text)
''';
      variables.addAll([
        Variable(
          PgDateTime(before.createdAt.toUtc()),
          PgTypes.timestampWithTimezone,
        ),
        Variable<String>(before.entryKey),
      ]);
    }
    final rows = await _db.customSelect(
      r'''
SELECT h.*, u.display_name AS actor_title
FROM (
  SELECT
    'r' || lpad(r.seq::text, 10, '0') AS entry_key,
    r.created_at,
    r.actor_id,
    r.seq,
    r.kind::integer AS kind,
    r.fact_text,
    r.restored_from_seq,
    NULL::integer AS type,
    NULL::integer AS visibility_from,
    NULL::integer AS visibility_to
  FROM public.beacon_fact_card_revision r
  WHERE r.fact_card_id = $1::text
  UNION ALL
  SELECT
    'e' || e.id AS entry_key,
    e.created_at,
    e.actor_id,
    NULL::integer,
    NULL::integer,
    NULL::text,
    NULL::integer,
    e.type::integer,
    (e.diff ->> 'previousVisibility')::integer,
    (e.diff ->> 'visibility')::integer
  FROM public.beacon_activity_event e
  WHERE e.fact_card_id = $1::text
    AND e.fact_card_id IS NOT NULL
    AND e.type IN (2, 14, 20)
) h
LEFT JOIN public."user" u ON u.id = h.actor_id
''' +
          cursorSql +
          r'''
ORDER BY h.created_at DESC, h.entry_key DESC
LIMIT $2::integer
''',
      variables: variables,
    ).get();
    return [for (final row in rows) _toHistoryEntry(row)];
  }

  static BeaconFactHistoryEntry _toHistoryEntry(QueryRow row) {
    final createdAt = _readTimestamp(row, 'created_at');
    final actorTitle = row.readNullable<String>('actor_title') ?? '';
    final actorId = row.readNullable<String>('actor_id');
    final seq = row.readNullable<int>('seq');
    if (seq != null) {
      return BeaconFactHistoryEntry.revision(
        seq: seq,
        kind: row.read<int>('kind'),
        factText: row.read<String>('fact_text'),
        actorTitle: actorTitle,
        createdAt: createdAt,
        restoredFromSeq: row.readNullable<int>('restored_from_seq'),
        actorId: actorId,
      );
    }
    return BeaconFactHistoryEntry.event(
      type: row.read<int>('type'),
      actorTitle: actorTitle,
      createdAt: createdAt,
      visibilityFrom: row.readNullable<int>('visibility_from'),
      visibilityTo: row.readNullable<int>('visibility_to'),
      actorId: actorId,
    );
  }

  static DateTime _readTimestamp(QueryRow row, String column) {
    final value = row.data[column];
    if (value is DateTime) return value.toUtc();
    if (value is PgDateTime) return value.dateTime.toUtc();
    return DateTime.parse(value.toString()).toUtc();
  }

  static DateTime? _readNullableTimestamp(QueryRow row, String column) =>
      row.data[column] == null ? null : _readTimestamp(row, column);
}
