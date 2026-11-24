import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

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
  Future<String?> lockActive(
    OwnerGraphScope scope,
    PhantomMergeTarget target,
  ) async {
    requireOwnerGraphScope(_database, scope, target.ownerId);
    final row = await _database
        .customSelect(
          r'''
SELECT display_name FROM public.phantom
WHERE owner_id = $1 AND id = $2 AND merged_at IS NULL
FOR UPDATE
''',
          variables: [
            Variable.withString(target.ownerId),
            Variable.withString(target.phantomId),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('display_name');
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
    await _recordOwnerAttention(target, mergeId);
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
    PhantomMergeTarget target,
    String mergeId,
  ) => _database.customStatement(
    r'''
WITH occurrence AS (
  INSERT INTO public.attention_occurrence (
    source_event_key, event_type, actor_user_id, immutable_payload
  )
  VALUES ($1, 'phantomMerged', $2, jsonb_build_object('targetEntityId', $3::text, 'mergeId', $4::text))
  RETURNING id
)
INSERT INTO public.attention_occurrence_recipient (
  occurrence_id, account_id, reasons, role_facts, collapse_key, channel_eligible
)
SELECT id, $2, '["owner"]'::jsonb, jsonb_build_object('targetEntityId', $3::text), $1, false
FROM occurrence
''',
    ['phantomMerged:$mergeId', target.ownerId, target.phantomId, mergeId],
  );
}
