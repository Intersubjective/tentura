import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
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

  /// Fact still shown in room (active or corrected).
  Future<BeaconFactCardEntity?> findNonRemovedBySourceMessage({
    required String beaconId,
    required String sourceMessageId,
  }) async {
    final rows = await _db.managers.beaconFactCards.filter(
      (r) =>
          r.beaconId.id(beaconId) &
          r.sourceMessageId.equals(sourceMessageId) &
          (r.status.equals(BeaconFactCardStatusBits.active) |
              r.status.equals(BeaconFactCardStatusBits.corrected)),
    ).get();
    if (rows.isEmpty) return null;
    rows.sort((a, b) => b.createdAt.dateTime.compareTo(a.createdAt.dateTime));
    return _toEntity(rows.first);
  }

  BeaconFactCardEntity _toEntity(BeaconFactCard row) => BeaconFactCardEntity(
        id: row.id,
        beaconId: row.beaconId,
        factText: row.factText,
        visibility: row.visibility,
        pinnedBy: row.pinnedBy,
        createdAt: row.createdAt.dateTime,
        sourceMessageId: row.sourceMessageId,
        status: row.status,
        updatedAt: row.updatedAt.dateTime,
      );

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

  /// Inserts a fact, optionally links [sourceMessageId], emits a system room line.
  Future<BeaconFactCardEntity> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    required String pinnedBy,
    String? sourceMessageId,
  }) =>
      _db.withMutatingUser(pinnedBy, () async {
        final trimmed = factText.trim();
        if (trimmed.isEmpty) {
          throw ArgumentError('factText');
        }
        if (sourceMessageId != null) {
          final smid = sourceMessageId;
          final msg = await _db.managers.beaconRoomMessages
              .filter((m) => m.id.equals(smid))
              .getSingleOrNull();
          if (msg == null || msg.beaconId != beaconId) {
            throw ArgumentError('sourceMessageId');
          }
        }
        final id = generateId('F');
        final row = await _db.managers.beaconFactCards.createReturning(
          (o) => o(
            id: Value(id),
            beaconId: beaconId,
            factText: trimmed,
            visibility: visibility,
            pinnedBy: pinnedBy,
            sourceMessageId: Value(sourceMessageId),
            status: const Value(BeaconFactCardStatusBits.active),
            createdAt: const Value.absent(),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
        if (sourceMessageId != null) {
          await _db.managers.beaconRoomMessages
              .filter((m) => m.id.equals(sourceMessageId))
              .update(
                (u) => u(linkedFactCardId: Value(row.id)),
              );
        }
        await _db.managers.beaconFactCardRevisions.create(
          (o) => o(
            id: generateId('FR'),
            factCardId: row.id,
            seq: 1,
            factText: trimmed,
            actorId: Value(pinnedBy),
            kind: BeaconFactCardRevisionKindBits.created,
          ),
        );
        final roomMsg = await _room.insertRoomMessage(
          beaconId: beaconId,
          authorId: pinnedBy,
          body: '',
          semanticMarker:
              visibility == BeaconFactCardVisibilityBits.public
              ? BeaconRoomSemanticMarker.pinFactPublic
              : BeaconRoomSemanticMarker.pinFactPrivate,
          systemPayload: {
            'factCardId': row.id,
            'factText': trimmed,
            'sourceMessageId': ?sourceMessageId,
          },
        );
        await _room.insertActivityEvent(
          beaconId: beaconId,
          visibility: visibility == BeaconFactCardVisibilityBits.public
              ? BeaconActivityEventVisibilityBits.public
              : BeaconActivityEventVisibilityBits.room,
          type: BeaconActivityEventTypeBits.factPinned,
          actorId: pinnedBy,
          sourceMessageId: sourceMessageId ?? roomMsg.id,
          diff: <String, Object?>{
            'factCardId': row.id,
            'factText': trimmed,
          },
        );
        return _toEntity(row);
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
