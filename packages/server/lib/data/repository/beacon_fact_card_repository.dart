import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/app/sentry/sentry_db_span.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_outcome.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';

@LazySingleton(as: BeaconFactCardRepositoryPort)
class BeaconFactCardRepository implements BeaconFactCardRepositoryPort {
  BeaconFactCardRepository(
    this._db,
    // Kept for DI; activity events are written inside the fact CTEs.
    // ignore: avoid_unused_constructor_parameters
    BeaconRoomRepositoryPort room,
  );

  final TenturaDb _db;

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
    final rows = await sentryDbSpan('db.fact.list', (span) async {
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
        variables: [
          Variable<String>(beaconId),
          Variable<bool>(includeRoomOnly),
        ],
      ).get();
      span?.setData('db.rows', rows.length);
      return rows;
    });
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

  /// Plan §8.6: newest live public fact (active or corrected) per beacon in
  /// one SELECT on `beacon_fact_card_public_live_idx`. Text is trimmed, then
  /// cut to 157 chars + `…` when over 160.
  @override
  Future<Map<String, String>> publicFactSnippetsByBeaconIds(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) return const {};
    final rows = await _db.customSelect(
      '''
SELECT DISTINCT ON (f.beacon_id) f.beacon_id, f.fact_text
FROM public.beacon_fact_card f
WHERE f.beacon_id = ANY(\$1::text[])
  AND f.visibility = ${BeaconFactCardVisibilityBits.public}
  AND f.status IN (${BeaconFactCardStatusBits.active}, ${BeaconFactCardStatusBits.corrected})
ORDER BY f.beacon_id, f.created_at DESC
''',
      variables: [Variable(TypedValue(Type.textArray, beaconIds))],
    ).get();
    return {
      for (final row in rows)
        row.read<String>('beacon_id'): _snippet(row.read<String>('fact_text')),
    };
  }

  static String _snippet(String factText) {
    final t = factText.trim();
    return t.length > 160 ? '${t.substring(0, 157)}…' : t;
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
      _db.withMutatingUser(pinnedBy, () => sentryDbSpan('db.fact.pin', (
        _,
      ) async {
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
        await _copySourceAttachmentsOntoRevision(factCardId: id, seq: 1);
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
      }));

  /// Copies the fact's source-message attachments into [seq]'s snapshot.
  Future<void> _copySourceAttachmentsOntoRevision({
    required String factCardId,
    required int seq,
  }) async {
    await _db.customUpdate(
      r'''
UPDATE public.beacon_fact_card_revision r
SET attachments_json = COALESCE((
  SELECT jsonb_agg(item ORDER BY (item->>'position')::int)
  FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
      'id', a.id,
      'kind', a.kind,
      'position', a.position,
      'mime', a.mime,
      'sizeBytes', a.size_bytes,
      'fileName', a.file_name,
      'imageId', COALESCE(i.id::text, ''),
      'imageAuthorId', COALESCE(i.author_id, ''),
      'blurHash', COALESCE(i.hash, ''),
      'width', COALESCE(i.width, 0),
      'height', COALESCE(i.height, 0)
    )) AS item
    FROM public.beacon_fact_card f
    JOIN public.beacon_room_message_attachment a
      ON a.message_id = f.source_message_id
    LEFT JOIN public.image i ON i.id = a.image_id
    WHERE f.id = $1::text
  ) q
), '[]'::jsonb)
WHERE r.fact_card_id = $1::text AND r.seq = $2::int
''',
      variables: [
        Variable<String>(factCardId),
        Variable<int>(seq),
      ],
      updates: {_db.beaconFactCardRevisions},
    );
  }

  @override
  Future<Map<String, String>> headAttachmentsJsonByFactIds(
    Iterable<String> factCardIds,
  ) async {
    final ids = factCardIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _db.customSelect(
      r'''
SELECT f.id, COALESCE(r.attachments_json::text, '[]') AS attachments_json
FROM public.beacon_fact_card f
LEFT JOIN public.beacon_fact_card_revision r
  ON r.fact_card_id = f.id AND r.seq = f.revision_seq
WHERE f.id = ANY($1::text[])
''',
      variables: [Variable(TypedValue(Type.textArray, ids))],
    ).get();
    return {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('attachments_json'),
    };
  }

  @override
  Future<String> attachmentsJsonForRevision({
    required String factCardId,
    required int seq,
  }) async {
    final row = await _db.customSelect(
      r'''
SELECT COALESCE(attachments_json::text, '[]') AS attachments_json
FROM public.beacon_fact_card_revision
WHERE fact_card_id = $1::text AND seq = $2::int
''',
      variables: [
        Variable<String>(factCardId),
        Variable<int>(seq),
      ],
    ).getSingleOrNull();
    return row?.read<String>('attachments_json') ?? '[]';
  }

  /// Plan §8.3 "Set visibility" / §14.3: one CTE updates the card and writes
  /// the `factVisibilityChanged` event with `fact_card_id` set. A
  /// visibility-only change does not advance `revision_seq`.
  @override
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
        final row = await _db.customSelect(
          '''
WITH prev AS (
  SELECT id, visibility AS previous_visibility
  FROM public.beacon_fact_card
  WHERE id = \$1::text AND beacon_id = \$2::text
  FOR UPDATE
),
fact AS (
  UPDATE public.beacon_fact_card f
  SET visibility = \$3::smallint, updated_at = now()
  FROM prev p
  WHERE f.id = p.id
  RETURNING f.id, f.beacon_id, f.source_message_id, p.previous_visibility
),
event AS (
  INSERT INTO public.beacon_activity_event
    (id, beacon_id, visibility, type, actor_id, source_message_id, diff,
     fact_card_id)
  SELECT \$5::text, f.beacon_id, \$6::smallint,
         ${BeaconActivityEventTypeBits.factVisibilityChanged}, \$4::text,
         f.source_message_id,
         jsonb_build_object(
           'factCardId', f.id,
           'previousVisibility', f.previous_visibility,
           'visibility', \$3::smallint
         ),
         f.id
  FROM fact f
)
SELECT count(*)::integer AS updated FROM fact
''',
          variables: [
            Variable<String>(factCardId),
            Variable<String>(beaconId),
            Variable<int>(visibility),
            Variable<String>(actorUserId),
            Variable<String>(BeaconActivityEventEntity.newId),
            Variable<int>(
              visibility == BeaconFactCardVisibilityBits.public
                  ? BeaconActivityEventVisibilityBits.public
                  : BeaconActivityEventVisibilityBits.room,
            ),
          ],
        ).getSingle();
        if (row.read<int>('updated') == 0) {
          throw IdNotFoundException(description: 'Fact card [$factCardId]');
        }
      });

  /// Plan §8.3 "Edit / restore" / §14.3: see [_runEdit].
  @override
  Future<FactEditOutcome> editText({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String newText,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
    String? attachmentsJson,
  }) => _runEdit(
    factCardId: factCardId,
    beaconId: beaconId,
    actorUserId: actorUserId,
    newText: newText.trim(),
    attachmentsJson: attachmentsJson,
    baseRevisionSeq: baseRevisionSeq,
    rateWindow: rateWindow,
    rateMax: rateMax,
    quietWindow: quietWindow,
    kind: BeaconFactCardRevisionKindBits.edited,
    fromSeq: null,
  );

  /// Plan §8.3 "Edit / restore" / §14.3: see [_runEdit].
  @override
  Future<FactEditOutcome> restoreRevision({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required int fromSeq,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
  }) => _runEdit(
    factCardId: factCardId,
    beaconId: beaconId,
    actorUserId: actorUserId,
    newText: null,
    attachmentsJson: null,
    baseRevisionSeq: baseRevisionSeq,
    rateWindow: rateWindow,
    rateMax: rateMax,
    quietWindow: quietWindow,
    kind: BeaconFactCardRevisionKindBits.restored,
    fromSeq: fromSeq,
  );

  /// Plan §14.9: the canonical edit / restore statement. `locked` reads the
  /// latest committed row `FOR UPDATE`; the CAS, rate limit, restore source
  /// gate and quiet window all live in the one CTE, and the diagnostic
  /// columns map to a [FactEditOutcome] in the order fixed by §8.3.
  ///
  /// `$14` is optional client attachments JSON (text). Restore copies from
  /// [fromSeq]; text-only edits with null `$14` copy the previous head
  /// snapshot; a change to text or attachments is a real write.
  Future<FactEditOutcome> _runEdit({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
    required String? newText,
    required String? attachmentsJson,
    required int baseRevisionSeq,
    required Duration rateWindow,
    required int rateMax,
    required Duration quietWindow,
    required int kind,
    required int? fromSeq,
  }) =>
      _db.withMutatingUser(actorUserId, () => sentryDbSpan('db.fact.edit', (
        _,
      ) async {
        final rows = await _db.customSelect(
          r'''
WITH locked AS (
  SELECT f.id, f.revision_seq, f.status, f.fact_text, f.pinned_by,
         f.created_at, f.visibility, f.source_message_id
  FROM public.beacon_fact_card f
  WHERE f.id = $1::text AND f.beacon_id = $2::text
  FOR UPDATE
),
src AS (
  SELECT r.fact_text, r.attachments_json
  FROM public.beacon_fact_card_revision r
  WHERE $13::int IS NOT NULL
    AND r.fact_card_id = $1::text AND r.seq = $13::int
),
head_att AS (
  SELECT COALESCE(r.attachments_json, '[]'::jsonb) AS attachments_json
  FROM locked l
  LEFT JOIN public.beacon_fact_card_revision r
    ON r.fact_card_id = l.id AND r.seq = l.revision_seq
),
input AS (
  SELECT COALESCE((SELECT s.fact_text FROM src s), $4::text) AS new_text,
         COALESCE(
           (SELECT s.attachments_json FROM src s),
           CASE WHEN $14::text IS NULL THEN NULL ELSE $14::text::jsonb END,
           (SELECT h.attachments_json FROM head_att h),
           '[]'::jsonb
         ) AS new_attachments,
         ($13::int IS NULL OR EXISTS (SELECT 1 FROM src)) AS src_ok,
         (SELECT count(*) FROM public.beacon_fact_card_revision r
          WHERE r.actor_id = $3::text
            AND r.created_at > now() - make_interval(secs => $6::int)
         ) < $7::int AS rate_ok
),
upd AS (
  UPDATE public.beacon_fact_card f
  SET fact_text          = input.new_text,
      status             = 1,
      revision_seq       = f.revision_seq + 1,
      last_edited_by     = $3::text,
      last_edited_at     = now(),
      updated_at         = now(),
      other_editor_count = f.other_editor_count + CASE
        WHEN $3::text IS DISTINCT FROM f.pinned_by
         AND NOT EXISTS (SELECT 1 FROM public.beacon_fact_card_revision r
                         WHERE r.fact_card_id = f.id AND r.actor_id = $3::text)
        THEN 1 ELSE 0 END
  FROM locked, input, head_att
  WHERE f.id = locked.id
    AND input.src_ok
    AND input.rate_ok
    AND input.new_text IS NOT NULL
    AND locked.status <> 2
    AND locked.revision_seq = $5::int
    AND (
      locked.fact_text IS DISTINCT FROM input.new_text
      OR head_att.attachments_json IS DISTINCT FROM input.new_attachments
    )
  RETURNING f.id, f.revision_seq, f.visibility, f.pinned_by, f.created_at,
            f.source_message_id
),
rev AS (
  INSERT INTO public.beacon_fact_card_revision
    (id, fact_card_id, seq, fact_text, actor_id, kind, restored_from_seq,
     attachments_json)
  SELECT $9::text, upd.id, upd.revision_seq, input.new_text, $3::text,
         $12::int, $13::int, input.new_attachments
  FROM upd, input
  RETURNING seq
),
quiet AS (
  SELECT (COALESCE($3::text = upd.pinned_by, false)
          AND upd.created_at > now() - make_interval(secs => $8::int)) AS q
  FROM upd
),
line AS (
  INSERT INTO public.beacon_room_message
    (id, beacon_id, author_id, body, semantic_marker, system_payload)
  SELECT $10::text, $2::text, $3::text, '', 10,
         jsonb_build_object('factCardId', upd.id,
                            'revisionSeq', upd.revision_seq,
                            'pinnedBy', upd.pinned_by,
                            'factText', left(input.new_text, 160))
  FROM upd, quiet, input
  WHERE NOT quiet.q
  RETURNING id
),
evt AS (
  INSERT INTO public.beacon_activity_event
    (id, beacon_id, visibility, type, actor_id, source_message_id,
     fact_card_id, diff)
  SELECT $11::text, $2::text, upd.visibility, 19, $3::text,
         COALESCE((SELECT l.id FROM line l), upd.source_message_id),
         upd.id,
         jsonb_build_object('factCardId', upd.id,
                            'revisionSeq', upd.revision_seq,
                            'kind', $12::int)
  FROM upd, quiet
  WHERE NOT quiet.q
)
SELECT (SELECT u.revision_seq FROM upd u)                    AS new_seq,
       EXISTS (SELECT 1 FROM locked)                         AS found,
       (SELECT l.status FROM locked l)                       AS current_status,
       (SELECT l.revision_seq FROM locked l)                 AS current_seq,
       (
         (SELECT l.fact_text FROM locked l)
           IS NOT DISTINCT FROM (SELECT i.new_text FROM input i)
         AND (SELECT h.attachments_json FROM head_att h)
           IS NOT DISTINCT FROM (SELECT i.new_attachments FROM input i)
       ) AS same_text,
       (SELECT i.src_ok FROM input i)                        AS src_ok,
       (SELECT i.rate_ok FROM input i)                       AS rate_ok;
''',
          variables: [
            Variable<String>(factCardId),
            Variable<String>(beaconId),
            Variable<String>(actorUserId),
            Variable<String>(newText),
            Variable<int>(baseRevisionSeq),
            Variable<int>(rateWindow.inSeconds),
            Variable<int>(rateMax),
            Variable<int>(quietWindow.inSeconds),
            Variable<String>(generateId('FR')),
            Variable<String>(generateId('R')),
            Variable<String>(BeaconActivityEventEntity.newId),
            Variable<int>(kind),
            Variable<int>(fromSeq),
            Variable<String>(attachmentsJson),
          ],
        ).get();
        final row = rows.single;
        final newSeq = row.readNullable<int>('new_seq');
        final found = row.read<bool>('found');
        final currentStatus = row.readNullable<int>('current_status');
        final currentSeq = row.readNullable<int>('current_seq');
        final sameText = row.readNullable<bool>('same_text');
        final srcOk = row.read<bool>('src_ok');
        final rateOk = row.read<bool>('rate_ok');
        if (newSeq != null) return FactEditApplied(newSeq: newSeq);
        if (!found) return const FactEditNotFound();
        if (!srcOk) return const FactRestoreSourceMissing();
        if (currentStatus == BeaconFactCardStatusBits.removed) {
          return const FactEditRemoved();
        }
        if (sameText ?? false) return FactEditNoOp(currentSeq: currentSeq!);
        if (!rateOk) return const FactEditRateLimited();
        return FactEditConflict(currentSeq: currentSeq!);
      }));

  /// Plan §8.3 "Unpin" / §14.4 rule 12: one CTE locks the fact, marks it
  /// removed, unlinks the source message by primary key, writes the marker-11
  /// line and the `factRemoved` event. Returns false when the fact was
  /// already removed; throws when it does not exist.
  @override
  Future<bool> remove({
    required String factCardId,
    required String beaconId,
    required String actorUserId,
  }) =>
      _db.withMutatingUser(actorUserId, () => sentryDbSpan('db.fact.remove', (
        _,
      ) async {
        final row = await _db.customSelect(
          '''
WITH locked AS (
  SELECT f.id, f.status
  FROM public.beacon_fact_card f
  WHERE f.id = \$1::text AND f.beacon_id = \$2::text
  FOR UPDATE
),
upd AS (
  UPDATE public.beacon_fact_card f
  SET status = ${BeaconFactCardStatusBits.removed}, updated_at = now()
  FROM locked l
  WHERE f.id = l.id AND l.status <> ${BeaconFactCardStatusBits.removed}
  RETURNING f.id, f.beacon_id, f.visibility, f.pinned_by, f.fact_text,
            f.source_message_id
),
unlink AS (
  UPDATE public.beacon_room_message m
  SET linked_fact_card_id = NULL
  FROM upd u
  WHERE m.id = u.source_message_id
),
line AS (
  INSERT INTO public.beacon_room_message
    (id, beacon_id, author_id, body, semantic_marker, system_payload)
  SELECT \$4::text, u.beacon_id, \$3::text, '',
         ${BeaconRoomSemanticMarker.factUnpinned},
         jsonb_build_object('factCardId', u.id,
                            'pinnedBy', u.pinned_by,
                            'factText', left(u.fact_text, 160))
  FROM upd u
  RETURNING id
),
evt AS (
  INSERT INTO public.beacon_activity_event
    (id, beacon_id, visibility, type, actor_id, source_message_id,
     fact_card_id, diff)
  SELECT \$5::text, u.beacon_id, u.visibility,
         ${BeaconActivityEventTypeBits.factRemoved}, \$3::text,
         COALESCE((SELECT l.id FROM line l), u.source_message_id),
         u.id,
         jsonb_build_object('factCardId', u.id)
  FROM upd u
)
SELECT EXISTS (SELECT 1 FROM locked) AS found,
       EXISTS (SELECT 1 FROM upd) AS removed
''',
          variables: [
            Variable<String>(factCardId),
            Variable<String>(beaconId),
            Variable<String>(actorUserId),
            Variable<String>(generateId('R')),
            Variable<String>(BeaconActivityEventEntity.newId),
          ],
        ).getSingle();
        if (!row.read<bool>('found')) {
          throw IdNotFoundException(description: 'Fact card [$factCardId]');
        }
        return row.read<bool>('removed');
      }));

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
    final rows = await sentryDbSpan(
      'db.fact.history',
      (_) => _db.customSelect(
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
      ).get(),
    );
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
    final entryKey = row.read<String>('entry_key');
    return BeaconFactHistoryEntry.event(
      activityEventId: entryKey.substring(1),
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
