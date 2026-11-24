import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/leased_job_retry.dart';

import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PhantomMergeRepositoryPort)
final class PhantomMergeRepository implements PhantomMergeRepositoryPort {
  const PhantomMergeRepository(this._database, this._anchors, this._contacts);

  final TenturaDb _database;
  final ScopedConstellationAnchorRepositoryPort _anchors;
  final UserContactRepositoryPort _contacts;

  @override
  Future<({String displayName, bool active})?> lockEntry(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  ) async {
    requireOwnerGraphScope(_database, scope, target.ownerId);
    final row = await _database
        .customSelect(
          r'''
SELECT display_name, merged_at IS NULL AS active FROM public.phantom
WHERE owner_id = $1 AND id = $2
FOR UPDATE
''',
          variables: [
            Variable.withString(target.ownerId),
            Variable.withString(target.phantomId),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : (
            displayName: row.read<String>('display_name'),
            active: row.read<bool>('active'),
          );
  }

  @override
  Future<List<PhantomMergeJobLease>> claimJobs({
    required String leaseOwner,
    required DateTime now,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
WITH due AS (
  SELECT id, attempts
  FROM public.phantom_merge_job
  WHERE state = 'queued' AND next_attempt_at <= $2::timestamptz
    AND (lease_until IS NULL OR lease_until <= $2::timestamptz)
  ORDER BY next_attempt_at, created_at, id
  FOR UPDATE SKIP LOCKED
  LIMIT 32
)
UPDATE public.phantom_merge_job AS job
SET lease_owner = $1, lease_until = $2::timestamptz + interval '2 minutes',
    attempts = LEAST(due.attempts + 1, $3)
FROM due
WHERE job.id = due.id
RETURNING job.*, due.attempts >= $3 AS exhausted
''',
          variables: [
            Variable.withString(leaseOwner),
            Variable(TypedValue(Type.timestampTz, now.toUtc())),
            Variable.withInt(kLeasedJobMaxAttempts),
          ],
        )
        .get();
    return [
      for (final row in rows)
        (
          id: row.read<String>('id'),
          target: (
            ownerId: row.read<String>('owner_id'),
            phantomId: row.read<String>('phantom_id'),
            userId: row.read<String>('user_id'),
          ),
          origin: PhantomMergeOrigin.fromCode(row.read<int>('origin')),
          leaseOwner: leaseOwner,
          attempts: row.read<int>('attempts'),
          exhausted: row.read<bool>('exhausted'),
        ),
    ];
  }

  static const _claimedJob = r'''
id = $1 AND lease_owner = $2 AND attempts = $3 AND state = 'queued'
''';

  List<Variable<Object>> _claimVariables(
    OwnerGraphScope scope,
    PhantomMergeJobLease job,
  ) {
    requireOwnerGraphScope(_database, scope, job.target.ownerId);
    return [
      Variable.withString(job.id),
      Variable.withString(job.leaseOwner),
      Variable.withInt(job.attempts),
    ];
  }

  @override
  Future<bool> lockClaim(
    OwnerGraphScope scope,
    PhantomMergeJobLease job,
  ) async {
    final row = await _database
        .customSelect(
          'SELECT 1 FROM public.phantom_merge_job WHERE $_claimedJob FOR UPDATE',
          variables: _claimVariables(scope, job),
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<bool> finishJob(
    OwnerGraphScope scope,
    PhantomMergeJobLease job, {
    String? skipReason,
  }) async {
    final count = await _database.customUpdate(
      r'''
UPDATE public.phantom_merge_job SET state = $4, reason = $5, done_at = now()
WHERE '''
      '$_claimedJob',
      variables: [
        ..._claimVariables(scope, job),
        Variable.withString(skipReason == null ? 'done' : 'skipped'),
        Variable<String>(skipReason),
      ],
      updateKind: UpdateKind.update,
    );
    return count == 1;
  }

  @override
  Future<bool> recordJobError(
    OwnerGraphScope scope,
    PhantomMergeJobLease job, {
    required String error,
    required DateTime? retryAt,
  }) async {
    final count = await _database.customUpdate(
      r'''
UPDATE public.phantom_merge_job
SET last_error = left($4, 1000),
    next_attempt_at = coalesce($5, next_attempt_at),
    lease_owner = NULL,
    lease_until = NULL,
    state = CASE WHEN $5 IS NULL THEN 'failed' ELSE 'queued' END,
    done_at = CASE WHEN $5 IS NULL THEN now() END
WHERE '''
      '$_claimedJob',
      variables: [
        ..._claimVariables(scope, job),
        Variable.withString(error),
        Variable(TypedValue(Type.timestampTz, retryAt?.toUtc())),
      ],
      updateKind: UpdateKind.update,
    );
    return count == 1;
  }

  @override
  Future<void> recordLinkCard(OwnerGraphScope scope, PhantomMergeJobLease job) {
    requireOwnerGraphScope(_database, scope, job.target.ownerId);
    return _recordOwnerAttention(
      job.target,
      eventType: 'phantomJoined',
      eventId: job.id,
      payload: {'userId': job.target.userId},
    );
  }

  @override
  Future<String> merge(
    OwnerGraphScope scope,
    PhantomMergeTarget target, {
    required PhantomMergeOrigin origin,
    required String displayName,
  }) async {
    final (:ownerId, :phantomId, :userId) = target;
    requireOwnerGraphScope(_database, scope, ownerId);
    final mergeId = generateId('PM');
    await _database.customStatement(
      r'''
INSERT INTO public.phantom_merge (id, phantom_id, owner_id, user_id, origin, undo)
VALUES ($1, $2, $3, $4, $5, '{}'::jsonb)
''',
      [mergeId, phantomId, ownerId, userId, origin.code],
    );

    final pinUndo = await _movePin(scope, target);
    final tagsUndo = await _copyTags(target);
    final contactUndo = await _writeContact(target, origin, displayName);

    await _database.customStatement(
      r'''
DELETE FROM public.invitation
WHERE user_id = $1 AND phantom_id = $2 AND invited_id IS NULL
''',
      [ownerId, phantomId],
    );
    await _database.customStatement(
      r'''
UPDATE public.phantom_merge SET undo = $2::jsonb || $3::jsonb WHERE id = $1
''',
      [
        mergeId,
        tagsUndo,
        jsonEncode({
          'pin': ?pinUndo,
          'contactName': {
            'before': contactUndo.before,
            'written': contactUndo.written,
          },
        }),
      ],
    );
    await _database.customStatement(
      r'''
UPDATE public.phantom
SET merged_user_id = $3, merged_at = now(), merge_origin = $4,
    current_merge_id = $5, revision = revision + 1, updated_at = now()
WHERE owner_id = $1 AND id = $2
''',
      [ownerId, phantomId, userId, origin.code, mergeId],
    );
    await _recordOwnerAttention(
      target,
      eventType: 'phantomMerged',
      eventId: mergeId,
      payload: {'mergeId': mergeId},
    );
    return mergeId;
  }

  Future<Map<String, Object?>?> _movePin(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  ) async {
    final (:ownerId, :phantomId, :userId) = target;
    final rows = await _database
        .customSelect(
          r'''
SELECT target_kind, tombstone_at IS NOT NULL AS tombstoned,
       x_units, y_units, coordinate_space_version
FROM public.constellation_anchor
WHERE viewer_id = $1 AND (
  (target_kind = 'PHANTOM' AND target_id = $2)
  OR (target_kind = 'PERSON' AND target_id = $3)
)
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(phantomId),
            Variable.withString(userId),
          ],
        )
        .get();
    final positions = <String, ConstellationAnchorPosition>{};
    for (final row in rows) {
      if (row.read<bool>('tombstoned')) {
        throw StateError('Cannot merge a tombstoned anchor for a live target');
      }
      positions[row.read<String>('target_kind')] = ConstellationAnchorPosition(
        xUnits: row.read<double>('x_units'),
        yUnits: row.read<double>('y_units'),
        coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
      );
    }
    final phantomPosition = positions['PHANTOM'];
    if (phantomPosition == null) return null;

    await _anchors.upsertScoped(
      scope: scope,
      viewerId: ownerId,
      target: ConstellationAnchorPersonTarget(userId),
      position: phantomPosition,
      additionalWatermarkTargets: {ConstellationAnchorPhantomTarget(phantomId)},
      forceRevision: true,
    );
    await _database.customStatement(
      r'''
DELETE FROM public.constellation_anchor
WHERE viewer_id = $1 AND target_kind = 'PHANTOM' AND target_id = $2
''',
      [ownerId, phantomId],
    );
    final watermark = await _database
        .customSelect(
          r'''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = $1 AND target_kind = 'PERSON' AND target_id = $2
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(userId),
          ],
        )
        .getSingle();
    return {
      'phantomPosition': _positionJson(phantomPosition),
      'previousPersonPosition': _positionJson(positions['PERSON']),
      'personWatermark': watermark.read<int>('revision'),
    };
  }

  static Map<String, Object>? _positionJson(
    ConstellationAnchorPosition? position,
  ) => position == null
      ? null
      : {
          'xUnits': position.xUnits,
          'yUnits': position.yUnits,
          'coordinateSpaceVersion': position.coordinateSpaceVersion,
        };

  Future<String> _copyTags(PhantomMergeTarget target) async {
    final row = await _database.customWriteReturning(
      r'''
WITH original AS MATERIALIZED (
  SELECT * FROM public.phantom_tag_member WHERE owner_id = $1 AND phantom_id = $2
), inserted AS (
  INSERT INTO public.person_tag_member (tag_id, owner_id, person_id, source)
  SELECT tag_id, owner_id, $3, source FROM original
  WHERE NOT public.block_hides($1, $3)
  ON CONFLICT (tag_id, person_id) DO NOTHING
  RETURNING membership_id
)
SELECT jsonb_build_object(
  'phantomMemberships', COALESCE(
    (SELECT jsonb_agg(to_jsonb(original) ORDER BY tag_id) FROM original), '[]'::jsonb
  ),
  'insertedMembershipIds', COALESCE(
    (SELECT jsonb_agg(membership_id ORDER BY membership_id) FROM inserted), '[]'::jsonb
  )
)::text AS undo
''',
      variables: [
        Variable.withString(target.ownerId),
        Variable.withString(target.phantomId),
        Variable.withString(target.userId),
      ],
    );
    return row.single.read<String>('undo');
  }

  Future<({String? before, String? written})> _writeContact(
    PhantomMergeTarget target,
    PhantomMergeOrigin origin,
    String displayName,
  ) async {
    final (:ownerId, :userId, phantomId: _) = target;
    final pair = [Variable.withString(ownerId), Variable.withString(userId)];

    while (true) {
      final existing = await _database.customSelect(
        r'''
SELECT contact_name FROM public.user_contact
WHERE viewer_id = $1 AND subject_id = $2 FOR UPDATE
''',
        variables: pair,
      ).getSingleOrNull();
      if (existing != null) {
        final before = existing.read<String>('contact_name');
        if (origin == PhantomMergeOrigin.manualLink) {
          return (before: before, written: null);
        }
        await _contacts.upsert(
          viewerId: ownerId,
          subjectId: userId,
          contactName: displayName,
        );
        return (before: before, written: displayName);
      }

      final inserted = await _database.customWriteReturning(
        r'''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES ($1, $2, $3)
ON CONFLICT (viewer_id, subject_id) DO NOTHING
RETURNING 1
''',
        variables: [...pair, Variable.withString(displayName)],
      );
      if (inserted.isNotEmpty) return (before: null, written: displayName);

      // An unscoped contact edit inserted the row after our read. Lock and
      // read it on a fresh snapshot before deciding what to record or write.
    }
  }

  Future<void> _recordOwnerAttention(
    PhantomMergeTarget target, {
    required String eventType,
    required String eventId,
    required Map<String, String> payload,
  }) => _database.customStatement(
    r'''
WITH occurrence AS (
  INSERT INTO public.attention_occurrence (
    source_event_key, event_type, actor_user_id, immutable_payload
  )
  VALUES ($1, $4, $2, $5::jsonb)
  ON CONFLICT (source_event_key) DO NOTHING
  RETURNING id
)
INSERT INTO public.attention_occurrence_recipient (
  occurrence_id, account_id, reasons, role_facts, collapse_key, channel_eligible
)
SELECT id, $2, '["owner"]'::jsonb, jsonb_build_object('targetEntityId', $3::text), $1, false
FROM occurrence
''',
    [
      '$eventType:$eventId',
      target.ownerId,
      target.phantomId,
      eventType,
      jsonEncode({'targetEntityId': target.phantomId, ...payload}),
    ],
  );
}
