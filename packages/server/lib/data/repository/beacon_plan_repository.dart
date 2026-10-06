import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart' show PgTypes;
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_plan.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';

import '../database/tentura_db.dart';

/// Request plan («либретто», #220) storage over m0223. Every statement is raw
/// SQL and joins the ambient transaction of the calling use case.
@Injectable(as: BeaconPlanRepositoryPort)
class BeaconPlanRepository implements BeaconPlanRepositoryPort {
  const BeaconPlanRepository(this._database);

  final TenturaDb _database;

  static const _stepColumns = '''
id, beacon_id, ordering, title, body, target_person_id, start_at, end_at,
done_at, done_by_id, created_seq, content_seq, ack_seq, removed_seq''';

  static DateTime? _ts(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static Object? _json(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) return null;
    if (value is String) return jsonDecode(value);
    return value;
  }

  static String? _instant(DateTime? v) => v?.toUtc().toIso8601String();

  PlanStepRecord _stepFromRow(QueryRow row) => PlanStepRecord(
    id: row.read<String>('id'),
    beaconId: row.read<String>('beacon_id'),
    ordering: row.read<int>('ordering'),
    title: row.read<String>('title'),
    description: row.read<String>('body'),
    assigneeId: row.readNullable<String>('target_person_id'),
    startAt: _ts(row, 'start_at'),
    endAt: _ts(row, 'end_at'),
    doneAt: _ts(row, 'done_at'),
    doneById: row.readNullable<String>('done_by_id'),
    createdSeq: row.read<int>('created_seq'),
    contentSeq: row.read<int>('content_seq'),
    ackSeq: row.read<int>('ack_seq'),
    removedSeq: row.readNullable<int>('removed_seq'),
  );

  BeaconPlanHead _headFromRow(QueryRow row) => BeaconPlanHead(
    beaconId: row.read<String>('beacon_id'),
    revisionSeq: row.read<int>('revision_seq'),
    changeSeq: row.read<int>('change_seq'),
    lastEditedById: row.readNullable<String>('last_edited_by'),
    lastEditedAt: _ts(row, 'last_edited_at'),
    copiedFromBeaconId: row.readNullable<String>('copied_from_beacon_id'),
  );

  PlanRevisionRecord _revisionFromRow(QueryRow row) {
    final changes = _json(row, 'changes_json');
    return PlanRevisionRecord(
      beaconId: row.read<String>('beacon_id'),
      seq: row.read<int>('seq'),
      baseSeq: row.readNullable<int>('base_seq'),
      kind: row.read<int>('kind'),
      actorId: row.readNullable<String>('actor_id'),
      restoredFromSeq: row.readNullable<int>('restored_from_seq'),
      comment: row.read<String>('comment'),
      snapshot: PlanSnapshot.fromJson(_json(row, 'steps_json')),
      changes: [
        if (changes is List)
          for (final c in changes)
            if (c is Map) c.cast<String, Object?>(),
      ],
      createdAt: _ts(row, 'created_at')!,
    );
  }

  @override
  Future<PlanRequestInfo?> requestInfo(String beaconId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT id, kind, status, user_id, title FROM public.beacon WHERE id = $1
''',
          variables: [Variable<String>(beaconId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return PlanRequestInfo(
      beaconId: row.read<String>('id'),
      kind: BeaconKind.fromValue(row.read<int>('kind')),
      status: BeaconStatus.fromSmallint(row.read<int>('status')),
      authorId: row.read<String>('user_id'),
      title: row.read<String>('title'),
    );
  }

  @override
  Future<BeaconPlanHead?> getHead(String beaconId) async {
    final row = await _database
        .customSelect(
          r'SELECT * FROM public.beacon_plan WHERE beacon_id = $1',
          variables: [Variable<String>(beaconId)],
        )
        .getSingleOrNull();
    return row == null ? null : _headFromRow(row);
  }

  @override
  Future<BeaconPlanHead> lockHead(String beaconId) async {
    await _database.customStatement(
      r'''
INSERT INTO public.beacon_plan (beacon_id) VALUES ($1)
ON CONFLICT (beacon_id) DO NOTHING
''',
      [beaconId],
    );
    final row = await _database
        .customSelect(
          r'SELECT * FROM public.beacon_plan WHERE beacon_id = $1 FOR UPDATE',
          variables: [Variable<String>(beaconId)],
        )
        .getSingle();
    return _headFromRow(row);
  }

  @override
  Future<List<PlanStepRecord>> liveSteps(String beaconId) async {
    final rows = await _database
        .customSelect(
          '''
SELECT $_stepColumns
FROM public.coordination_item
WHERE beacon_id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
  AND status = ${BeaconPlanConsts.stepStatusLive}
ORDER BY ordering, created_seq, id
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    return rows.map(_stepFromRow).toList();
  }

  @override
  Future<Map<String, PlanStepRecord>> stepsById(
    String beaconId,
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _database
        .customSelect(
          '''
SELECT $_stepColumns
FROM public.coordination_item
WHERE beacon_id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
  AND id = ANY(\$2::text[])
''',
          variables: [
            Variable<String>(beaconId),
            Variable<List<String>>(list, PgTypes.textArray),
          ],
        )
        .get();
    return {for (final r in rows.map(_stepFromRow)) r.id: r};
  }

  @override
  Future<Set<String>> foreignStepIds(
    String beaconId,
    Iterable<String> ids,
  ) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _database
        .customSelect(
          '''
SELECT id FROM public.coordination_item
WHERE id = ANY(\$2::text[])
  AND (beacon_id <> \$1 OR kind <> ${BeaconPlanConsts.stepKind})
''',
          variables: [
            Variable<String>(beaconId),
            Variable<List<String>>(list, PgTypes.textArray),
          ],
        )
        .get();
    return {for (final r in rows) r.read<String>('id')};
  }

  @override
  Future<PlanStepRecord?> getStep(String stepId) async {
    final row = await _database
        .customSelect(
          '''
SELECT $_stepColumns
FROM public.coordination_item
WHERE id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
''',
          variables: [Variable<String>(stepId)],
        )
        .getSingleOrNull();
    return row == null ? null : _stepFromRow(row);
  }

  static const _revisionColumns = '''
beacon_id, seq, base_seq, kind, actor_id, restored_from_seq, comment,
steps_json::text AS steps_json, changes_json::text AS changes_json,
created_at''';

  @override
  Future<PlanRevisionRecord?> getRevision(String beaconId, int seq) async {
    final row = await _database
        .customSelect(
          '''
SELECT $_revisionColumns
FROM public.beacon_plan_revision
WHERE beacon_id = \$1 AND seq = \$2
''',
          variables: [Variable<String>(beaconId), Variable<int>(seq)],
        )
        .getSingleOrNull();
    return row == null ? null : _revisionFromRow(row);
  }

  @override
  Future<List<PlanRevisionRecord>> listRevisions(
    String beaconId, {
    int? beforeSeq,
    int? afterSeq,
    int limit = 50,
  }) async {
    final rows = await _database
        .customSelect(
          '''
SELECT $_revisionColumns
FROM public.beacon_plan_revision
WHERE beacon_id = \$1
  AND (\$2::int IS NULL OR seq < \$2::int)
  AND (\$3::int IS NULL OR seq > \$3::int)
ORDER BY seq DESC
LIMIT \$4
''',
          variables: [
            Variable<String>(beaconId),
            Variable<int>(beforeSeq),
            Variable<int>(afterSeq),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows.map(_revisionFromRow).toList();
  }

  @override
  Future<int> countRevisionsByActorSince(
    String actorId,
    DateTime since,
  ) async {
    final row = await _database
        .customSelect(
          r'''
SELECT count(*)::int AS n FROM public.beacon_plan_revision
WHERE actor_id = $1 AND created_at >= $2::timestamptz
''',
          variables: [
            Variable<String>(actorId),
            Variable<String>(_instant(since)),
          ],
        )
        .getSingle();
    return row.read<int>('n');
  }

  @override
  Future<void> insertRevision({
    required String beaconId,
    required int seq,
    required int kind,
    required PlanSnapshot snapshot,
    required List<Map<String, Object?>> changes,
    int? baseSeq,
    String? actorId,
    int? restoredFromSeq,
    String comment = '',
  }) => _database.customStatement(
    r'''
INSERT INTO public.beacon_plan_revision
  (beacon_id, seq, base_seq, kind, actor_id, restored_from_seq, comment,
   steps_json, changes_json)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8::text::jsonb, $9::text::jsonb)
''',
    [
      beaconId,
      seq,
      baseSeq,
      kind,
      actorId,
      restoredFromSeq,
      comment,
      snapshot.encode(),
      jsonEncode(changes),
    ],
  );

  @override
  Future<void> writeSteps({
    required String beaconId,
    required int seq,
    required String? actorId,
    required PlanSnapshot snapshot,
    required Set<String> ackChangedIds,
  }) async {
    final existing = await _allSteps(beaconId);
    final keep = snapshot.ids.toSet();
    for (final step in existing.values) {
      if (step.isRemoved || keep.contains(step.id)) continue;
      await _database.customStatement(
        '''
UPDATE public.coordination_item
SET status = ${BeaconPlanConsts.stepStatusRemoved}, removed_seq = \$2,
    cancelled_at = now(), updated_at = now(), ack_seq = \$2
WHERE id = \$1
''',
        [step.id, seq],
      );
    }
    var ordering = 0;
    for (final step in snapshot.steps) {
      ordering++;
      final old = existing[step.id];
      if (old == null) {
        await _database.customStatement(
          '''
INSERT INTO public.coordination_item
  (id, beacon_id, kind, status, title, body, creator_id, target_person_id,
   ordering, published, published_at, start_at, end_at,
   created_seq, content_seq, ack_seq)
VALUES (\$1, \$2, ${BeaconPlanConsts.stepKind},
        ${BeaconPlanConsts.stepStatusLive}, \$3, \$4, \$5, \$6, \$7, true,
        now(), \$8::timestamptz, \$9::timestamptz, \$10, \$10, \$10)
''',
          [
            step.id,
            beaconId,
            step.title,
            step.description,
            actorId,
            step.assigneeId,
            ordering,
            _instant(step.startAt),
            _instant(step.endAt),
            seq,
          ],
        );
        continue;
      }
      final contentChanged = old.isRemoved || !old.snapshot.sameContentAs(step);
      final ackChanged = old.isRemoved || ackChangedIds.contains(step.id);
      if (!contentChanged && old.ordering == ordering) continue;
      await _database.customStatement(
        '''
UPDATE public.coordination_item
SET title = \$2, body = \$3, target_person_id = \$4,
    start_at = \$5::timestamptz, end_at = \$6::timestamptz, ordering = \$7,
    status = ${BeaconPlanConsts.stepStatusLive}, removed_seq = NULL,
    cancelled_at = NULL,
    content_seq = CASE WHEN \$8 THEN \$10 ELSE content_seq END,
    ack_seq = CASE WHEN \$9 THEN \$10 ELSE ack_seq END,
    updated_at = now()
WHERE id = \$1
''',
        [
          step.id,
          step.title,
          step.description,
          step.assigneeId,
          _instant(step.startAt),
          _instant(step.endAt),
          ordering,
          contentChanged,
          ackChanged,
          seq,
        ],
      );
    }
  }

  Future<Map<String, PlanStepRecord>> _allSteps(String beaconId) async {
    final rows = await _database
        .customSelect(
          '''
SELECT $_stepColumns
FROM public.coordination_item
WHERE beacon_id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    return {for (final r in rows.map(_stepFromRow)) r.id: r};
  }

  @override
  Future<void> touchHead(
    String beaconId, {
    int? revisionSeq,
    String? editedById,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_plan
SET change_seq = change_seq + 1,
    revision_seq = COALESCE($2, revision_seq),
    last_edited_by = CASE WHEN $2 IS NULL THEN last_edited_by ELSE $3 END,
    last_edited_at = CASE WHEN $2 IS NULL THEN last_edited_at ELSE now() END,
    updated_at = now()
WHERE beacon_id = $1
''',
    [beaconId, revisionSeq, editedById],
  );

  @override
  Future<void> setCopiedFrom({
    required String beaconId,
    required String sourceBeaconId,
  }) => _database.customStatement(
    r'''
UPDATE public.beacon_plan SET copied_from_beacon_id = $2 WHERE beacon_id = $1
''',
    [beaconId, sourceBeaconId],
  );

  @override
  Future<bool> setDone({
    required String stepId,
    required String actorId,
  }) async {
    final rows = await _database
        .customSelect(
          '''
UPDATE public.coordination_item
SET done_at = now(), done_by_id = \$2, updated_at = now()
WHERE id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
  AND status = ${BeaconPlanConsts.stepStatusLive} AND done_at IS NULL
RETURNING id
''',
          variables: [Variable<String>(stepId), Variable<String>(actorId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<bool> clearDone(String stepId) async {
    final rows = await _database
        .customSelect(
          '''
UPDATE public.coordination_item
SET done_at = NULL, done_by_id = NULL, updated_at = now()
WHERE id = \$1 AND kind = ${BeaconPlanConsts.stepKind}
  AND status = ${BeaconPlanConsts.stepStatusLive} AND done_at IS NOT NULL
RETURNING id
''',
          variables: [Variable<String>(stepId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  PlanMemberRecord _memberFromRow(QueryRow row) => PlanMemberRecord(
    beaconId: row.read<String>('beacon_id'),
    userId: row.read<String>('user_id'),
    pendingFromSeq: row.readNullable<int>('pending_from_seq'),
    ackedSeq: row.read<int>('acked_seq'),
    ackedAt: _ts(row, 'acked_at'),
  );

  @override
  Future<PlanMemberRecord?> getMember(String beaconId, String userId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT * FROM public.beacon_plan_member WHERE beacon_id = $1 AND user_id = $2
''',
          variables: [Variable<String>(beaconId), Variable<String>(userId)],
        )
        .getSingleOrNull();
    return row == null ? null : _memberFromRow(row);
  }

  @override
  Future<List<PlanMemberRecord>> listMembers(String beaconId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT * FROM public.beacon_plan_member WHERE beacon_id = $1 ORDER BY user_id
''',
          variables: [Variable<String>(beaconId)],
        )
        .get();
    return rows.map(_memberFromRow).toList();
  }

  @override
  Future<void> markPending(
    String beaconId,
    Set<String> userIds,
    int seq,
  ) async {
    for (final userId in userIds) {
      await _database.customStatement(
        r'''
INSERT INTO public.beacon_plan_member (beacon_id, user_id, pending_from_seq)
SELECT $1, $2, $3
WHERE EXISTS (SELECT 1 FROM public."user" u WHERE u.id = $2)
ON CONFLICT (beacon_id, user_id) DO UPDATE
SET pending_from_seq = COALESCE(beacon_plan_member.pending_from_seq, $3)
''',
        [beaconId, userId, seq],
      );
    }
  }

  @override
  Future<void> writeAck({
    required String beaconId,
    required String userId,
    required int ackedSeq,
    required int? pendingFromSeq,
  }) => _database.customStatement(
    r'''
INSERT INTO public.beacon_plan_member
  (beacon_id, user_id, pending_from_seq, acked_seq, acked_at)
VALUES ($1, $2, $3, $4, now())
ON CONFLICT (beacon_id, user_id) DO UPDATE
SET pending_from_seq = $3,
    acked_seq = GREATEST(beacon_plan_member.acked_seq, $4),
    acked_at = now()
''',
    [beaconId, userId, pendingFromSeq, ackedSeq],
  );

  @override
  Future<void> clearPending(String beaconId, String userId) =>
      _database.customStatement(
        r'''
UPDATE public.beacon_plan_member SET pending_from_seq = NULL
WHERE beacon_id = $1 AND user_id = $2
''',
        [beaconId, userId],
      );

  @override
  Future<Map<String, String>> displayNames(Iterable<String> userIds) async {
    final list = userIds.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _database
        .customSelect(
          r'''
SELECT id, display_name FROM public."user" WHERE id = ANY($1::text[])
''',
          variables: [Variable<List<String>>(list, PgTypes.textArray)],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): r.read<String>('display_name'),
    };
  }

  @override
  Future<String> insertPlanLine({
    required String beaconId,
    required String? actorId,
    required int marker,
    required Map<String, Object?> payload,
  }) async {
    final row = await _database
        .customSelect(
          r'''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, semantic_marker, system_payload,
   system_message_kind)
VALUES ($1, $2, '', $3, $4::text::jsonb, $5)
RETURNING id
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(actorId),
            Variable<int>(marker),
            Variable<String>(jsonEncode(payload)),
            const Variable<int>(BeaconRoomSystemMessageKind.plan),
          ],
        )
        .getSingle();
    return row.read<String>('id');
  }

  PlanTailMessage _tailFromRow(QueryRow row) {
    final payload = _json(row, 'system_payload');
    return PlanTailMessage(
      id: row.read<String>('id'),
      marker: row.readNullable<int>('semantic_marker'),
      createdAt: _ts(row, 'created_at')!,
      payload: payload is Map ? payload.cast<String, Object?>() : null,
    );
  }

  @override
  Future<PlanTailMessage?> tailMainRoomMessage(String beaconId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT id, semantic_marker, created_at,
       system_payload::text AS system_payload
FROM public.beacon_room_message
WHERE beacon_id = $1 AND thread_item_id IS NULL
ORDER BY created_at DESC, id DESC
LIMIT 1
''',
          variables: [Variable<String>(beaconId)],
        )
        .getSingleOrNull();
    return row == null ? null : _tailFromRow(row);
  }

  @override
  Future<void> updateLinePayload(
    String messageId,
    Map<String, Object?> payload,
  ) => _database.customStatement(
    r'''
UPDATE public.beacon_room_message
SET system_payload = $2::text::jsonb
WHERE id = $1
''',
    [messageId, jsonEncode(payload)],
  );

  @override
  Future<PlanTailMessage?> latestTickLineFor(
    String beaconId,
    String stepId,
  ) async {
    final row = await _database
        .customSelect(
          '''
SELECT id, semantic_marker, created_at,
       system_payload::text AS system_payload
FROM public.beacon_room_message
WHERE beacon_id = \$1
  AND semantic_marker = ${BeaconRoomSemanticMarker.planStepsDone}
  AND system_payload -> 'ticks' @> jsonb_build_array(
        jsonb_build_object('stepId', \$2::text))
ORDER BY created_at DESC, id DESC
LIMIT 1
''',
          variables: [Variable<String>(beaconId), Variable<String>(stepId)],
        )
        .getSingleOrNull();
    return row == null ? null : _tailFromRow(row);
  }

  @override
  Future<void> insertActivity({
    required String beaconId,
    required int type,
    required String? actorId,
    String? stepId,
    String? targetUserId,
    String? sourceMessageId,
    Map<String, Object?>? diff,
  }) => _database.customStatement(
    r'''
INSERT INTO public.beacon_activity_event
  (beacon_id, visibility, type, actor_id, target_user_id, source_message_id,
   coordination_item_id, diff)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8::text::jsonb)
''',
    [
      beaconId,
      BeaconActivityEventVisibilityBits.room,
      type,
      actorId,
      targetUserId,
      sourceMessageId,
      stepId,
      if (diff == null) null else jsonEncode(diff),
    ],
  );

  @override
  Future<Map<String, PlanSliceSource>> sliceSourcesFor(
    String userId,
    Iterable<String> beaconIds,
  ) async {
    final list = beaconIds.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _database
        .customSelect(
          '''
SELECT b.id AS beacon_id, b.status,
  COALESCE(h.revision_seq, 0) AS revision_seq,
  m.pending_from_seq,
  (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', ci.id, 'ordering', ci.ordering, 'title', ci.title,
      'body', ci.body, 'assigneeId', ci.target_person_id,
      'startAt', ci.start_at, 'endAt', ci.end_at, 'doneAt', ci.done_at,
      'doneById', ci.done_by_id, 'createdSeq', ci.created_seq,
      'contentSeq', ci.content_seq, 'ackSeq', ci.ack_seq)
      ORDER BY ci.ordering, ci.created_seq, ci.id), '[]'::jsonb)
   FROM public.coordination_item ci
   WHERE ci.beacon_id = b.id AND ci.kind = ${BeaconPlanConsts.stepKind}
     AND ci.status = ${BeaconPlanConsts.stepStatusLive})::text AS steps,
  (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'seq', r.seq, 'actorId', r.actor_id, 'changes', r.changes_json,
      'createdAt', r.created_at,
      'actorName', (SELECT u.display_name FROM public."user" u
                    WHERE u.id = r.actor_id)) ORDER BY r.seq), '[]'::jsonb)
   FROM public.beacon_plan_revision r
   WHERE m.pending_from_seq IS NOT NULL AND r.beacon_id = b.id
     AND r.seq >= m.pending_from_seq)::text AS pending_revisions
FROM public.beacon b
LEFT JOIN public.beacon_plan h ON h.beacon_id = b.id
LEFT JOIN public.beacon_plan_member m
  ON m.beacon_id = b.id AND m.user_id = \$1
WHERE b.id = ANY(\$2::text[]) AND b.kind = ${BeaconKind.request.value}
''',
          variables: [
            Variable<String>(userId),
            Variable<List<String>>(list, PgTypes.textArray),
          ],
        )
        .get();
    final out = <String, PlanSliceSource>{};
    for (final row in rows) {
      final beaconId = row.read<String>('beacon_id');
      final rawSteps = _json(row, 'steps');
      final rawRevisions = _json(row, 'pending_revisions');
      out[beaconId] = PlanSliceSource(
        beaconId: beaconId,
        status: BeaconStatus.fromSmallint(row.read<int>('status')),
        revisionSeq: row.read<int>('revision_seq'),
        pendingFromSeq: row.readNullable<int>('pending_from_seq'),
        steps: [
          if (rawSteps is List)
            for (final s in rawSteps)
              if (s is Map) _sliceStep(beaconId, s.cast<String, Object?>()),
        ],
        pendingRevisions: [
          if (rawRevisions is List)
            for (final r in rawRevisions)
              if (r is Map) _sliceRevision(r.cast<String, Object?>()),
        ],
      );
    }
    return out;
  }

  static DateTime? _jsonTs(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  static int _jsonInt(Object? v) => v is num ? v.toInt() : 0;

  static PlanStepRecord _sliceStep(String beaconId, Map<String, Object?> s) =>
      PlanStepRecord(
        id: s['id']! as String,
        beaconId: beaconId,
        ordering: _jsonInt(s['ordering']),
        title: (s['title'] as String?) ?? '',
        description: (s['body'] as String?) ?? '',
        assigneeId: s['assigneeId'] as String?,
        startAt: _jsonTs(s['startAt']),
        endAt: _jsonTs(s['endAt']),
        doneAt: _jsonTs(s['doneAt']),
        doneById: s['doneById'] as String?,
        createdSeq: _jsonInt(s['createdSeq']),
        contentSeq: _jsonInt(s['contentSeq']),
        ackSeq: _jsonInt(s['ackSeq']),
      );

  static PlanPendingRevision _sliceRevision(Map<String, Object?> r) {
    final changes = r['changes'];
    return PlanPendingRevision(
      seq: _jsonInt(r['seq']),
      actorId: r['actorId'] as String?,
      actorName: r['actorName'] as String?,
      changes: [
        if (changes is List)
          for (final c in changes)
            if (c is Map) c.cast<String, Object?>(),
      ],
      createdAt:
          _jsonTs(r['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
