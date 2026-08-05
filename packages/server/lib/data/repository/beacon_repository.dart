import 'package:drift/drift.dart' show QueryRow;
import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime, UuidValue;
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts.dart'
    show kTitleMaxLength, kTitleMinLength;
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/beacon_mapper.dart';

export 'package:tentura_server/domain/entity/beacon_entity.dart';

/// Matches Postgres `beacon_context_name_length`: NULL or length in
/// [kTitleMinLength, kTitleMaxLength] (see `m0001` beacon table).
String? _beaconContextForDb(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.length < kTitleMinLength) return null;
  if (t.length > kTitleMaxLength) {
    return t.substring(0, kTitleMaxLength);
  }
  return t;
}

@Injectable(
  as: BeaconRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class BeaconRepository implements BeaconRepositoryPort {
  const BeaconRepository(this._database);

  final TenturaDb _database;

  @override
  Future<BeaconEntity> createBeacon({
    required String authorId,
    required String title,
    String? description,
    String? context,
    List<String>? imageIds,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    int ticker = 0,
    String? primaryNeedSlug,
    String? coverImageId,
    BeaconCoverSource coverSource = BeaconCoverSource.photo,
    BeaconStatus? status,
    String? addressLabel,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) => _database.withMutatingUser(authorId, () async {
    final effectiveStatus = status ?? BeaconStatus.open;
    var beacon = await _database.managers.beacons.createReturning(
      (o) => o(
        userId: authorId,
        title: title,
        context: Value(_beaconContextForDb(context)),
        description: Value(description ?? ''),
        ticker: Value(ticker),
        lat: Value(latitude),
        long: Value(longitude),
        startAt: Value(startAt == null ? null : PgDateTime(startAt)),
        endAt: Value(endAt == null ? null : PgDateTime(endAt)),
        tags: Value.absentIfNull(tags?.join(',')),
        needs: Value(needs == null || needs.isEmpty ? '' : needs.join(',')),
        primaryNeedSlug: Value(primaryNeedSlug),
        coverSource: Value(coverSource.wireValue),
        status: Value(effectiveStatus.smallintValue),
        addressLabel: Value(addressLabel),
        lineageParentBeaconId: Value(lineageParentBeaconId),
        lineageRootBeaconId: Value(lineageRootBeaconId),
      ),
    );

    if (imageIds != null && imageIds.isNotEmpty) {
      await _database.managers.beaconImages.bulkCreate(
        (o) => [
          for (var i = 0; i < imageIds.length; i++)
            o(
              beaconId: beacon.id,
              imageId: UuidValue.fromString(imageIds[i]),
              position: Value(i),
            ),
        ],
      );
      // Set cover last so the composite membership FK sees the attachment
      // row inserted just above (same transaction, same-tx visibility).
      final effectiveCover = coverImageId ?? imageIds.first;
      await _database.managers.beacons
          .filter((e) => e.id.equals(beacon.id))
          .update(
            (o) => o(coverImageId: Value(UuidValue.fromString(effectiveCover))),
          );
      beacon = await _database.managers.beacons
          .filter((e) => e.id.equals(beacon.id))
          .getSingle();
    }

    if (effectiveStatus == BeaconStatus.open) {
      await _insertBeaconPublishedEvent(
        beaconId: beacon.id,
        actorId: authorId,
        title: title,
      );
    }

    final author = await _database.managers.users
        .filter((e) => e.id.equals(authorId))
        .getSingle();

    final images = await _getBeaconImages(beacon.id);

    return beaconModelToEntity(
      beacon,
      author: author,
      images: images,
    );
  });

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    final (beacon, author) = await _database.managers.beacons
        .filter(
          filterByUserId == null
              ? (e) => e.id.equals(beaconId)
              : (e) =>
                    e.id.equals(beaconId) & e.userId.id.equals(filterByUserId),
        )
        .withReferences((p) => p(userId: true))
        .getSingle();

    final images = await _getBeaconImages(beaconId);
    final authorRow = await author.userId.getSingle();

    return beaconModelToEntity(
      beacon,
      author: authorRow,
      images: images,
    );
  }

  @override
  Future<BeaconEntity> updateDraftBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    Set<String>? needs,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? primaryNeedSlug,
    String? addressLabel,
  }) => _database.withMutatingUser(userId, () async {
    final row = await _database.managers.beacons
        .filter(
          (e) => e.id.equals(beaconId) & e.userId.id.equals(userId),
        )
        .withReferences((p) => p(userId: true))
        .getSingleOrNull();

    if (row == null) {
      throw const BeaconCreateException(
        description: 'Request is not an editable draft',
      );
    }
    final (existing, _) = row;

    if (existing.status != BeaconStatus.draft.smallintValue) {
      throw const BeaconCreateException(
        description: 'Request is not an editable draft',
      );
    }

    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update(
          (o) => o(
            title: Value(title),
            description: Value(description),
            context: Value(_beaconContextForDb(context)),
            tags: Value(
              tags == null || tags.isEmpty ? '' : tags.join(','),
            ),
            needs: Value(
              needs == null || needs.isEmpty ? '' : needs.join(','),
            ),
            lat: Value(latitude),
            long: Value(longitude),
            startAt: Value(startAt == null ? null : PgDateTime(startAt)),
            endAt: Value(endAt == null ? null : PgDateTime(endAt)),
            primaryNeedSlug: Value(primaryNeedSlug),
            addressLabel: Value(addressLabel),
          ),
        );

    return getBeaconById(beaconId: beaconId, filterByUserId: userId);
  });

  @override
  Future<BeaconEntity> updateBeacon({
    required String beaconId,
    required String userId,
    required String title,
    required String description,
    String? context,
    Set<String>? tags,
    Set<String>? needs,
    DateTime? startAt,
    DateTime? endAt,
    double? latitude,
    double? longitude,
    String? primaryNeedSlug,
    String? addressLabel,
  }) => _database.withMutatingUser(userId, () async {
    final row = await _database.managers.beacons
        .filter(
          (e) => e.id.equals(beaconId) & e.userId.id.equals(userId),
        )
        .getSingleOrNull();

    if (row == null) {
      throw const BeaconCreateException(
        description: 'Request not found or not owned by user',
      );
    }

    final current = BeaconStatus.fromSmallint(row.status);
    if (!current.isOpenFamily && current != BeaconStatus.reviewOpen) {
      throw const BeaconCreateException(
        description: 'Only open or wrapping-up requests can be edited',
      );
    }

    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update(
          (o) => o(
            title: Value(title),
            description: Value(description),
            context: Value(_beaconContextForDb(context)),
            tags: Value(
              tags == null || tags.isEmpty ? '' : tags.join(','),
            ),
            needs: Value(
              needs == null || needs.isEmpty ? '' : needs.join(','),
            ),
            lat: Value(latitude),
            long: Value(longitude),
            startAt: Value(startAt == null ? null : PgDateTime(startAt)),
            endAt: Value(endAt == null ? null : PgDateTime(endAt)),
            primaryNeedSlug: Value(primaryNeedSlug),
            addressLabel: Value(addressLabel),
          ),
        );

    return getBeaconById(beaconId: beaconId, filterByUserId: userId);
  });

  @override
  Future<void> deleteBeaconById(String id, {required String userId}) =>
      _database.withMutatingUser(userId, () async {
        await _database.managers.beacons
            .filter((e) => e.id.equals(id))
            .delete();
      });

  @override
  Future<T> runInBeaconStateTransaction<T>({
    required String beaconId,
    required String userId,
    required Future<T> Function(BeaconEntity locked) fn,
  }) => _database.withMutatingUser(userId, () async {
    await _database
        .customSelect(
          r'SELECT id FROM public.beacon WHERE id = $1 FOR UPDATE',
          variables: [Variable<String>(beaconId)],
        )
        .getSingle();

    final locked = await getBeaconById(beaconId: beaconId);
    return fn(locked);
  });

  @override
  Future<void> recordBeaconStatusTransition({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    required String? actorId,
  }) => _database.transaction(() async {
    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update(
          (o) => o(
            status: Value(toStatus.smallintValue),
            statusChangedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
    await _insertBeaconLifecycleEvent(
      beaconId: beaconId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      reason: reason,
      actorId: actorId,
    );
  });

  @override
  Future<void> addImage({
    required String beaconId,
    required String imageId,
    required int position,
  }) => _database.managers.beaconImages.create(
    (o) => o(
      beaconId: beaconId,
      imageId: UuidValue.fromString(imageId),
      position: Value(position),
    ),
  );

  @override
  Future<void> removeImage({
    required String beaconId,
    required String imageId,
  }) => _database.managers.beaconImages
      .filter(
        (e) =>
            e.beaconId.id.equals(beaconId) &
            e.imageId.id(UuidValue.fromString(imageId)),
      )
      .delete();

  @override
  Future<int> getImageCount(String beaconId) => _database.managers.beaconImages
      .filter((e) => e.beaconId.id.equals(beaconId))
      .count();

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final rows = await _database
        .customSelect(
          r'''
SELECT COUNT(*)::int AS c
FROM public.beacon
WHERE user_id = $1 AND created_at >= $2
''',
          variables: [
            Variable<String>(userId),
            Variable(TypedValue(Type.timestampTz, since)),
          ],
        )
        .getSingle();
    return rows.read<int>('c');
  }

  @override
  Future<void> reorderImages({
    required String beaconId,
    required List<String> imageIds,
  }) async {
    for (var i = 0; i < imageIds.length; i++) {
      await _database.managers.beaconImages
          .filter(
            (e) =>
                e.beaconId.id.equals(beaconId) &
                e.imageId.id(UuidValue.fromString(imageIds[i])),
          )
          .update((o) => o(position: Value(i)));
    }
  }

  @override
  Future<BeaconEntity> publishDraft({
    required String id,
    required String actorId,
  }) => _database.withMutatingUser(actorId, () async {
    return _database.transaction(() async {
      final existing = await _database.managers.beacons
          .filter(
            (e) => e.id.equals(id) & e.userId.id.equals(actorId),
          )
          .getSingleOrNull();

      if (existing == null) {
        throw const BeaconCreateException(
          description: 'Request not found or not owned',
        );
      }

      if (existing.status != BeaconStatus.draft.smallintValue) {
        return getBeaconById(beaconId: id, filterByUserId: actorId);
      }

      await _database.managers.beacons
          .filter((e) => e.id.equals(id))
          .update(
            (o) => o(
              status: Value(BeaconStatus.open.smallintValue),
              statusChangedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          );

      await _insertBeaconPublishedEvent(
        beaconId: id,
        actorId: actorId,
        title: existing.title,
      );

      return getBeaconById(beaconId: id, filterByUserId: actorId);
    });
  });

  Future<void> _insertBeaconPublishedEvent({
    required String beaconId,
    required String actorId,
    String? title,
  }) async {
    final diff = <String, Object?>{};
    final trimmedTitle = title?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      diff['title'] = trimmedTitle;
    }

    await _database.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.public,
        type: BeaconActivityEventTypeBits.beaconPublished,
        actorId: Value(actorId),
        diff: diff.isEmpty ? const Value(null) : Value(diff),
        createdAt: const Value.absent(),
      ),
    );
  }

  Future<void> _insertBeaconLifecycleEvent({
    required String beaconId,
    required BeaconStatus fromStatus,
    required BeaconStatus toStatus,
    required String reason,
    required String? actorId,
  }) async {
    await _database.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.public,
        type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
        actorId: actorId == null ? const Value(null) : Value(actorId),
        diff: Value(<String, Object?>{
          'fromState': fromStatus.smallintValue,
          'toState': toStatus.smallintValue,
          'fromStatus': fromStatus.smallintValue,
          'toStatus': toStatus.smallintValue,
          'reason': reason,
        }),
        createdAt: const Value.absent(),
      ),
    );
  }

  Future<List<Image>> _getBeaconImages(String beaconId) async {
    final beaconImageRows = await _database.managers.beaconImages
        .filter((e) => e.beaconId.id.equals(beaconId))
        .orderBy((e) => e.position.asc())
        .get();

    if (beaconImageRows.isEmpty) return const [];

    final imageIds = beaconImageRows.map((e) => e.imageId).toList();
    final imageRows = await _database.managers.images
        .filter((e) => e.id.isIn(imageIds))
        .get();

    final imageMap = {for (final img in imageRows) img.id: img};
    return [
      for (final bi in beaconImageRows) ?imageMap[bi.imageId],
    ];
  }

  @override
  Future<BeaconMediaSnapshot> getMediaSnapshot(String beaconId) async {
    final attachedRows = await _database.managers.beaconImages
        .filter((e) => e.beaconId.id.equals(beaconId))
        .orderBy((e) => e.position.asc())
        .get();
    final stagedRows = await _database.managers.beaconImageStages
        .filter((e) => e.beaconId.id.equals(beaconId))
        .get();
    return BeaconMediaSnapshot(
      attachedImageIds: [for (final row in attachedRows) row.imageId.uuid],
      stagedImageIds: {for (final row in stagedRows) row.imageId.uuid},
    );
  }

  @override
  Future<void> insertStage({
    required String beaconId,
    required String imageId,
  }) => _database.managers.beaconImageStages.create(
    (o) => o(beaconId: beaconId, imageId: UuidValue.fromString(imageId)),
  );

  @override
  Future<void> deleteStage({required String imageId}) =>
      _database.managers.beaconImageStages
          .filter((e) => e.imageId.id(UuidValue.fromString(imageId)))
          .delete();

  @override
  Future<void> setCover({
    required String beaconId,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  }) => _database.managers.beacons.filter((e) => e.id.equals(beaconId)).update(
    (o) => o(
      coverImageId: coverImageId == null
          ? const Value(null)
          : Value(UuidValue.fromString(coverImageId)),
      coverSource: Value(coverSource.wireValue),
      coverThumbImageId: const Value(null),
    ),
  );

  @override
  Future<List<String>> replaceMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
    String? coverThumbImageId,
  }) async {
    final currentAttachedIds = (await _database.managers.beaconImages
            .filter((e) => e.beaconId.id.equals(beaconId))
            .get())
        .map((e) => e.imageId.uuid)
        .toSet();
    final currentStagedIds = (await _database.managers.beaconImageStages
            .filter((e) => e.beaconId.id.equals(beaconId))
            .get())
        .map((e) => e.imageId.uuid)
        .toSet();

    final desired = imageIds.toSet();
    final toDetach = currentAttachedIds.difference(desired);
    final toDiscardStage = currentStagedIds.difference(desired);

    for (final imageId in toDetach) {
      await _database.managers.beaconImages
          .filter(
            (e) =>
                e.beaconId.id.equals(beaconId) &
                e.imageId.id(UuidValue.fromString(imageId)),
          )
          .delete();
    }
    for (final imageId in toDiscardStage) {
      await _database.managers.beaconImageStages
          .filter((e) => e.imageId.id(UuidValue.fromString(imageId)))
          .delete();
    }

    // Deferrable `beacon_image_position_uq` permits transient duplicate
    // positions here; it is enforced at commit.
    for (var i = 0; i < imageIds.length; i++) {
      final imageId = imageIds[i];
      if (currentAttachedIds.contains(imageId)) {
        await _database.managers.beaconImages
            .filter(
              (e) =>
                  e.beaconId.id.equals(beaconId) &
                  e.imageId.id(UuidValue.fromString(imageId)),
            )
            .update((o) => o(position: Value(i)));
      } else {
        await _database.managers.beaconImageStages
            .filter((e) => e.imageId.id(UuidValue.fromString(imageId)))
            .delete();
        await _database.managers.beaconImages.create(
          (o) => o(
            beaconId: beaconId,
            imageId: UuidValue.fromString(imageId),
            position: Value(i),
          ),
        );
      }
    }

    await _database.managers.beacons.filter((e) => e.id.equals(beaconId)).update(
      (o) => o(
        coverImageId: coverImageId == null
            ? const Value(null)
            : Value(UuidValue.fromString(coverImageId)),
        coverSource: Value(coverSource.wireValue),
        coverThumbImageId: coverThumbImageId == null
            ? const Value(null)
            : Value(UuidValue.fromString(coverThumbImageId)),
      ),
    );

    if (coverThumbImageId != null &&
        currentStagedIds.contains(coverThumbImageId)) {
      await deleteStage(imageId: coverThumbImageId);
    }

    return [...toDetach, ...toDiscardStage];
  }

  @override
  Future<int> reviewReopenCount(String beaconId) async {
    final row = await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingle();
    return row.reviewReopenCount;
  }

  @override
  Future<void> incrementReviewReopenCount(String beaconId) async {
    final row = await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingle();
    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update(
          (o) => o(reviewReopenCount: Value(row.reviewReopenCount + 1)),
        );
  }

  @override
  Future<List<BeaconStageRow>> staleStages({
    required DateTime olderThan,
    int limit = 100,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT s.beacon_id, s.image_id, s.staged_at, b.user_id AS author_id
FROM public.beacon_image_stage AS s
JOIN public.beacon AS b ON b.id = s.beacon_id
WHERE s.staged_at <= $1
ORDER BY s.staged_at, s.beacon_id, s.image_id
LIMIT $2
''',
          variables: [
            Variable(TypedValue(Type.timestampTz, olderThan.toUtc())),
            Variable(TypedValue(Type.integer, limit)),
          ],
        )
        .get();
    return [
      for (final row in rows)
        BeaconStageRow(
          beaconId: row.read<String>('beacon_id'),
          imageId: _readUuid(row, 'image_id'),
          authorId: row.read<String>('author_id'),
          stagedAt: row.read<PgDateTime>('staged_at').dateTime,
        ),
    ];
  }

  static String _readUuid(QueryRow row, String column) {
    final value = row.data[column];
    return value is UuidValue ? value.uuid : value.toString();
  }
}
