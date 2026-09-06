import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/port/user_erasure_port.dart';

import '../database/tentura_db.dart';

/// Non-personal placeholders satisfying live beacon CHECK constraints (§4.5).
abstract final class UserErasureScrubPlaceholders {
  static const title = 'Deleted request';
  static const description = 'This request was deleted.';
}

@Singleton(as: UserErasurePort)
class UserErasureRepository implements UserErasurePort {
  UserErasureRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<OwnedPublishedBeaconRow>> listOwnedPublishedBeacons({
    required String userId,
  }) async {
    final rows = await _database.customSelect(
      r'''
SELECT id, status
FROM public.beacon
WHERE user_id = $1
  AND published_at IS NOT NULL
  AND status <> $2
ORDER BY id
''',
      variables: [
        Variable<String>(userId),
        Variable<int>(BeaconStatus.draft.smallintValue),
      ],
    ).get();
    return [
      for (final row in rows)
        OwnedPublishedBeaconRow(
          beaconId: row.read<String>('id'),
          status: BeaconStatus.fromSmallint(row.read<int>('status')),
        ),
    ];
  }

  @override
  Future<List<String>> listOwnedDraftBeaconIds({required String userId}) async {
    final rows = await _database.customSelect(
      r'''
SELECT id
FROM public.beacon
WHERE user_id = $1
  AND status = $2
ORDER BY id
''',
      variables: [
        Variable<String>(userId),
        Variable<int>(BeaconStatus.draft.smallintValue),
      ],
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  @override
  Future<List<String>> scrubDeletedOwnedBeaconContent({
    required String beaconId,
    required String ownerId,
  }) async {
    final imageIds = await _collectBeaconOwnedImageIds(
      beaconId: beaconId,
      ownerId: ownerId,
    );
    await _database.customStatement(
      r'''
UPDATE public.beacon
SET title = $3,
    description = $4,
    context = NULL,
    lat = NULL,
    long = NULL,
    address_label = NULL,
    start_at = NULL,
    end_at = NULL,
    tags = '',
    needs = '',
    primary_need_slug = NULL,
    cover_image_id = NULL,
    cover_thumb_image_id = NULL,
    cover_source = 0
WHERE id = $1
  AND user_id = $2
''',
      [
        beaconId,
        ownerId,
        UserErasureScrubPlaceholders.title,
        UserErasureScrubPlaceholders.description,
      ],
    );
    await _database.customStatement(
      r'DELETE FROM public.beacon_image WHERE beacon_id = $1',
      [beaconId],
    );
    await _database.customStatement(
      r'DELETE FROM public.beacon_image_stage WHERE beacon_id = $1',
      [beaconId],
    );
    if (imageIds.isNotEmpty) {
      await _deleteImageRows(imageIds: imageIds, authorId: ownerId);
    }
    return imageIds;
  }

  @override
  Future<List<String>> hardDeleteOwnedDraftBeacon({
    required String beaconId,
    required String ownerId,
  }) async {
    final imageIds = await _collectBeaconOwnedImageIds(
      beaconId: beaconId,
      ownerId: ownerId,
    );
    await _database.customStatement(
      r'DELETE FROM public.beacon WHERE id = $1 AND user_id = $2',
      [beaconId, ownerId],
    );
    if (imageIds.isNotEmpty) {
      await _deleteImageRows(imageIds: imageIds, authorId: ownerId);
    }
    return imageIds;
  }

  @override
  Future<void> deleteUserScopedEvaluationAndCapabilityRows({
    required String userId,
  }) async {
    await _database.customStatement(
      r'''
DELETE FROM public.beacon_evaluation_ack_tag
WHERE evaluator_id = $1 OR subject_id = $1
''',
      [userId],
    );
    await _database.customStatement(
      r'''
DELETE FROM public.beacon_evaluation_visibility
WHERE evaluator_id = $1 OR participant_id = $1
''',
      [userId],
    );
    await _database.customStatement(
      r'DELETE FROM public.beacon_evaluation_participant WHERE user_id = $1',
      [userId],
    );
    await _database.customStatement(
      r'''
DELETE FROM public.beacon_evaluation
WHERE evaluator_id = $1 OR evaluated_user_id = $1
''',
      [userId],
    );
    await _database.customStatement(
      r'''
DELETE FROM public.person_capability_event
WHERE observer_user_id = $1 OR subject_user_id = $1
''',
      [userId],
    );
  }

  @override
  Future<void> deleteOrdinaryRoomMessagesAuthoredByUser({
    required String userId,
  }) async {
    await _database.customStatement(
      r'''
DELETE FROM public.beacon_room_message
WHERE author_id = $1
  AND system_message_kind IS NULL
''',
      [userId],
    );
  }

  @override
  Future<List<String>> deleteOwnedImageRows({required String userId}) async {
    final rows = await _database.customSelect(
      r'SELECT id::text AS id FROM public.image WHERE author_id = $1',
      variables: [Variable<String>(userId)],
    ).get();
    final imageIds = [for (final row in rows) row.read<String>('id')];
    if (imageIds.isEmpty) {
      return const [];
    }
    await _deleteImageRows(imageIds: imageIds, authorId: userId);
    return imageIds;
  }

  Future<List<String>> _collectBeaconOwnedImageIds({
    required String beaconId,
    required String ownerId,
  }) async {
    final rows = await _database.customSelect(
      r'''
SELECT DISTINCT image_id::text AS id
FROM (
  SELECT bi.image_id
  FROM public.beacon_image bi
  WHERE bi.beacon_id = $1
  UNION
  SELECT b.cover_image_id
  FROM public.beacon b
  WHERE b.id = $1 AND b.user_id = $2 AND b.cover_image_id IS NOT NULL
  UNION
  SELECT b.cover_thumb_image_id
  FROM public.beacon b
  WHERE b.id = $1 AND b.user_id = $2 AND b.cover_thumb_image_id IS NOT NULL
  UNION
  SELECT s.image_id
  FROM public.beacon_image_stage s
  WHERE s.beacon_id = $1
) owned
WHERE image_id IS NOT NULL
''',
      variables: [
        Variable<String>(beaconId),
        Variable<String>(ownerId),
      ],
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  Future<void> _deleteImageRows({
    required List<String> imageIds,
    required String authorId,
  }) async {
    await _database.customStatement(
      r'''
DELETE FROM public.image
WHERE author_id = $1
  AND id = ANY($2::uuid[])
''',
      [authorId, imageIds],
    );
  }
}
