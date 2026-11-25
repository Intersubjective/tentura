import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/leased_job_retry.dart';

import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_repository_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;
import 'attention_dispatch_repository.dart';
import 'field_population_sql.dart';
import 'owner_graph_unit_of_work.dart';
import 'phantom_tag_transfer.dart';

typedef _PinUndo = ({
  ConstellationAnchorPosition phantomPosition,
  ConstellationAnchorPosition? previousPersonPosition,
  int personWatermark,
});

@LazySingleton(as: PhantomMergeRepositoryPort)
final class PhantomMergeRepository implements PhantomMergeRepositoryPort {
  const PhantomMergeRepository(
    this._database,
    this._anchors,
    this._contacts,
    this._attention,
  );

  final TenturaDb _database;
  final ScopedConstellationAnchorRepositoryPort _anchors;
  final UserContactRepositoryPort _contacts;
  final AttentionDispatchRepository _attention;

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
  Future<bool> isInFieldPopulation(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  ) async {
    final (:ownerId, :userId, phantomId: _) = target;
    requireOwnerGraphScope(_database, scope, ownerId);
    final row = await _database
        .customSelect(
          '''
WITH $fieldPopulationCtesSql
SELECT EXISTS (
  SELECT 1 FROM public."user" u
  WHERE u.id = \$3 AND NOT public.block_hides(\$1, u.id)
    AND u.id IN (SELECT id FROM population)
) AS eligible
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(kConstellationContext),
            Variable.withString(userId),
          ],
        )
        .getSingle();
    return row.read<bool>('eligible');
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
    final variables = _claimVariables(scope, job);
    // Erasure locks the account before cascading to the job. Match that order
    // so a worker waiting on the account never holds the job row.
    final account = await _database
        .customSelect(
          r'SELECT id FROM public."user" WHERE id = $1 FOR KEY SHARE',
          variables: [Variable.withString(job.target.userId)],
        )
        .getSingleOrNull();
    if (account == null) return false;
    final row = await _database
        .customSelect(
          'SELECT 1 FROM public.phantom_merge_job WHERE $_claimedJob FOR UPDATE',
          variables: variables,
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
    return _attention.recordPersonJoined(
      ownerId: job.target.ownerId,
      phantomId: job.target.phantomId,
      jobId: job.id,
      userId: job.target.userId,
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
    await transferPhantomTags(
      _database,
      scope,
      ownerId: ownerId,
      mergeId: mergeId,
    );
    final copiedAvatarKey = await _copyAvatar(target);
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
UPDATE public.phantom_merge SET undo = undo || $2::jsonb WHERE id = $1
''',
      [
        mergeId,
        jsonEncode({
          'pin': ?pinUndo,
          if (copiedAvatarKey != null)
            'avatar': {'subjectUserId': userId, 'objectKey': copiedAvatarKey},
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
    await _attention.recordPersonMerged(
      ownerId: ownerId,
      phantomId: phantomId,
      mergeId: mergeId,
      displayName: displayName,
    );
    return mergeId;
  }

  @override
  Future<String?> lockCurrentMerge(
    OwnerGraphScope scope, {
    required String ownerId,
    required String phantomId,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final row = await _database
        .customSelect(
          r'''
SELECT m.id FROM public.phantom p
JOIN public.phantom_merge m ON m.id = p.current_merge_id
  AND m.phantom_id = p.id AND m.owner_id = p.owner_id
  AND m.user_id = p.merged_user_id AND m.origin = p.merge_origin
WHERE p.owner_id = $1 AND p.id = $2 AND p.merged_at IS NOT NULL
  AND m.undone_at IS NULL
FOR UPDATE OF p, m
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(phantomId),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('id');
  }

  @override
  Future<void> unmerge(
    OwnerGraphScope scope, {
    required String ownerId,
    required String mergeId,
  }) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final merge = await _database
        .customSelect(
          r'''
SELECT phantom_id, user_id, origin, undo->>'pin' AS pin,
       CASE WHEN undo #>> '{avatar,subjectUserId}' = user_id
            THEN undo #>> '{avatar,objectKey}' END AS copied_avatar_key,
       undo #>> '{contactName,before}' AS previous_name,
       undo #>> '{contactName,written}' AS written_name
FROM public.phantom_merge WHERE owner_id = $1 AND id = $2
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(mergeId),
          ],
        )
        .getSingle();
    final target = (
      ownerId: ownerId,
      phantomId: merge.read<String>('phantom_id'),
      userId: merge.read<String>('user_id'),
    );
    final origin = PhantomMergeOrigin.fromCode(merge.read<int>('origin'));
    final pin = _decodePinUndo(merge.readNullable<String>('pin'));
    await _database.customStatement(
      r'''
DELETE FROM public.person_tag_member AS member
USING public.phantom_merge AS m
WHERE m.id = $3 AND member.owner_id = $1 AND member.person_id = $2
  AND member.membership_id IN (
    SELECT value::uuid FROM jsonb_array_elements_text(m.undo->'insertedMembershipIds')
  )
''',
      [ownerId, target.userId, mergeId],
    );
    await _database.customStatement(
      r'''
WITH reactivated AS (
  UPDATE public.phantom
  SET merged_user_id = NULL, merged_at = NULL, merge_origin = NULL,
      current_merge_id = NULL, revision = revision + 1, updated_at = now()
  WHERE owner_id = $1 AND current_merge_id = $2 AND id = $3
  RETURNING id
)
UPDATE public.phantom_merge SET undone_at = now()
WHERE id = $2 AND phantom_id IN (SELECT id FROM reactivated)
''',
      [ownerId, mergeId, target.phantomId],
    );
    await _restorePins(scope, target, pin);
    final copiedAvatarKey = merge.readNullable<String>('copied_avatar_key');
    if (copiedAvatarKey != null) {
      await _removeCopiedAvatar(target, copiedAvatarKey);
    }
    await _restoreContactName(
      target,
      previous: merge.readNullable<String>('previous_name'),
      written: merge.readNullable<String>('written_name'),
    );
    if (origin != PhantomMergeOrigin.manualLink) {
      final pair = [ownerId, target.userId];
      // Like vote writes and Block, change the vote before locking its
      // projection. Projecting takes the pair lock itself.
      await _database.customStatement(
        r'DELETE FROM public.vote_user WHERE subject = $1 AND object = $2',
        pair,
      );
      await _database.customStatement(
        r'SELECT public.trust_project_pair($1, $2)',
        pair,
      );
    }
  }

  Future<String?> _copyAvatar(PhantomMergeTarget target) async {
    final (:ownerId, :phantomId, :userId) = target;
    final rows = await _database.customWriteReturning(
      r'''
INSERT INTO public.person_private_avatar
  (owner_id, subject_user_id, object_key, blurhash, width, height)
SELECT owner_id, $3, object_key, blurhash, width, height
FROM public.person_private_avatar
WHERE owner_id = $1 AND subject_phantom_id = $2
ON CONFLICT (owner_id, subject_user_id, subject_phantom_id) DO NOTHING
RETURNING object_key
''',
      variables: [
        Variable.withString(ownerId),
        Variable.withString(phantomId),
        Variable.withString(userId),
      ],
    );
    return rows.singleOrNull?.read<String>('object_key');
  }

  Future<void> _removeCopiedAvatar(
    PhantomMergeTarget target,
    String objectKey,
  ) async {
    final removed = await _database.customUpdate(
      r'''
DELETE FROM public.person_private_avatar
WHERE owner_id = $1 AND subject_user_id = $2 AND object_key = $3
''',
      variables: [
        Variable.withString(target.ownerId),
        Variable.withString(target.userId),
        Variable.withString(objectKey),
      ],
      updateKind: UpdateKind.delete,
    );
    if (removed == 0) return;

    // The delete trigger queued this key and holds its GC lock until commit.
    // A removal of the last reference will enqueue again under the same lock.
    await _database.customStatement(
      r'''
DELETE FROM public.private_object_gc gc
WHERE gc.object_key = $1 AND EXISTS (
  SELECT 1 FROM public.person_private_avatar WHERE object_key = gc.object_key
)
''',
      [objectKey],
    );
  }

  Future<void> _restorePins(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
    _PinUndo? pin,
  ) async {
    final (:ownerId, :phantomId, :userId) = target;
    final person = ConstellationAnchorPersonTarget(userId);
    final phantom = ConstellationAnchorPhantomTarget(phantomId);
    if (pin == null ||
        pin.personWatermark != await _targetWatermark(ownerId, person)) {
      await _anchors.advanceScopedWatermarks(
        scope: scope,
        viewerId: ownerId,
        targets: {person, phantom},
      );
      return;
    }

    final prior = pin.previousPersonPosition;
    if (prior == null) {
      await _deletePin(ownerId, person);
    } else {
      await _anchors.upsertScoped(
        scope: scope,
        viewerId: ownerId,
        target: person,
        position: prior,
        additionalWatermarkTargets: const {},
        forceRevision: true,
      );
    }
    await _anchors.upsertScoped(
      scope: scope,
      viewerId: ownerId,
      target: phantom,
      position: pin.phantomPosition,
      additionalWatermarkTargets: {if (prior == null) person},
      forceRevision: true,
    );
  }

  static _PinUndo? _decodePinUndo(String? pin) => pin == null
      ? null
      : switch (jsonDecode(pin)) {
          {
            'phantomPosition': final phantom,
            'previousPersonPosition': final previous,
            'personWatermark': final int watermark,
          } =>
            (
              phantomPosition: _decodePosition(phantom),
              previousPersonPosition: previous == null
                  ? null
                  : _decodePosition(previous),
              personWatermark: watermark,
            ),
          _ => throw StateError('Invalid merge pin undo record'),
        };

  static ConstellationAnchorPosition _decodePosition(Object? value) =>
      switch (value) {
        {
          'xUnits': final num x,
          'yUnits': final num y,
          'coordinateSpaceVersion': final int version,
        } =>
          ConstellationAnchorPosition(
            xUnits: x.toDouble(),
            yUnits: y.toDouble(),
            coordinateSpaceVersion: version,
          ),
        _ => throw StateError('Invalid merge pin position'),
      };

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
    final person = ConstellationAnchorPersonTarget(userId);
    final phantom = ConstellationAnchorPhantomTarget(phantomId);

    await _anchors.upsertScoped(
      scope: scope,
      viewerId: ownerId,
      target: person,
      position: phantomPosition,
      additionalWatermarkTargets: {phantom},
      forceRevision: true,
    );
    await _deletePin(ownerId, phantom);
    final watermark = await _targetWatermark(ownerId, person);
    if (watermark == null) throw StateError('Merge pin watermark is missing');
    return {
      'phantomPosition': _positionJson(phantomPosition),
      'previousPersonPosition': _positionJson(positions['PERSON']),
      'personWatermark': watermark,
    };
  }

  Future<void> _deletePin(String ownerId, ConstellationAnchorTarget target) =>
      _database.customStatement(
        r'''
DELETE FROM public.constellation_anchor
WHERE viewer_id = $1 AND target_kind = $2 AND target_id = $3
''',
        [ownerId, target.kind.wireValue, target.id],
      );

  Future<int?> _targetWatermark(
    String ownerId,
    ConstellationAnchorTarget target,
  ) async {
    final row = await _database
        .customSelect(
          r'''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = $1 AND target_kind = $2 AND target_id = $3
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(target.kind.wireValue),
            Variable.withString(target.id),
          ],
        )
        .getSingleOrNull();
    return row?.read<int>('revision');
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

  Future<({String? before, String? written})> _writeContact(
    PhantomMergeTarget target,
    PhantomMergeOrigin origin,
    String displayName,
  ) async {
    final (:ownerId, :userId, phantomId: _) = target;
    final pair = [Variable.withString(ownerId), Variable.withString(userId)];

    while (true) {
      final before = await _lockContactName(ownerId, userId);
      if (before != null) {
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

  Future<void> _restoreContactName(
    PhantomMergeTarget target, {
    required String? previous,
    required String? written,
  }) async {
    if (written == null || previous == written) return;
    final (:ownerId, :userId, phantomId: _) = target;
    if (await _lockContactName(ownerId, userId) != written) return;
    if (previous == null) {
      await _contacts.delete(viewerId: ownerId, subjectId: userId);
    } else {
      await _contacts.upsert(
        viewerId: ownerId,
        subjectId: userId,
        contactName: previous,
      );
    }
  }

  Future<String?> _lockContactName(String ownerId, String userId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT contact_name FROM public.user_contact
WHERE viewer_id = $1 AND subject_id = $2 FOR UPDATE
''',
          variables: [
            Variable.withString(ownerId),
            Variable.withString(userId),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('contact_name');
  }
}
