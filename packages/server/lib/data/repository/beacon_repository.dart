import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime, UuidValue;
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts.dart' show kTitleMaxLength, kTitleMinLength;
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
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
    String? iconCode,
    int? iconBackground,
    BeaconStatus? status,
    String? needSummary,
    String? successCriteria,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) => _database.withMutatingUser(authorId, () async {
    final effectiveStatus = status ?? BeaconStatus.open;
    final beacon = await _database.managers.beacons.createReturning(
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
        iconCode: Value(iconCode),
        iconBackground: Value(iconBackground),
        status: Value(effectiveStatus.smallintValue),
        needSummary: Value(needSummary),
        successCriteria: Value(successCriteria),
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
    }

    if (effectiveStatus == BeaconStatus.open) {
      await _insertBeaconPublishedEvent(
        beaconId: beacon.id,
        actorId: authorId,
        title: title,
        needSummary: needSummary,
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
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
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

    await _database.managers.beacons.filter((e) => e.id.equals(beaconId)).update(
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
        iconCode: Value(iconCode),
        iconBackground: Value(iconBackground),
        needSummary: Value(needSummary),
        successCriteria: Value(successCriteria),
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
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
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

    await _database.managers.beacons.filter((e) => e.id.equals(beaconId)).update(
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
        iconCode: Value(iconCode),
        iconBackground: Value(iconBackground),
        needSummary: Value(needSummary),
        successCriteria: Value(successCriteria),
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
  }) =>
      _database.withMutatingUser(userId, () async {
        await _database.customSelect(
          r'SELECT id FROM public.beacon WHERE id = $1 FOR UPDATE',
          variables: [Variable<String>(beaconId)],
        ).getSingle();

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
  }) =>
      _database.transaction(() async {
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
  Future<int> getImageCount(String beaconId) =>
      _database.managers.beaconImages
          .filter((e) => e.beaconId.id.equals(beaconId))
          .count();

  @override
  Future<int> countRecentByAuthor({
    required String userId,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final rows = await _database.customSelect(
      '''
SELECT COUNT(*)::int AS c
FROM public.beacon
WHERE user_id = \$1 AND created_at >= \$2
''',
      variables: [
        Variable<String>(userId),
        Variable(TypedValue(Type.timestampTz, since)),
      ],
    ).getSingle();
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
  }) =>
      _database.withMutatingUser(actorId, () async {
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
            needSummary: existing.needSummary,
          );

          return getBeaconById(beaconId: id, filterByUserId: actorId);
        });
      });

  Future<void> _insertBeaconPublishedEvent({
    required String beaconId,
    required String actorId,
    String? title,
    String? needSummary,
  }) async {
    final diff = <String, Object?>{};
    final trimmedTitle = title?.trim();
    final trimmedSummary = needSummary?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      diff['title'] = trimmedTitle;
    }
    if (trimmedSummary != null && trimmedSummary.isNotEmpty) {
      diff['needSummary'] = trimmedSummary;
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
      for (final bi in beaconImageRows)
        ?imageMap[bi.imageId],
    ];
  }
}
