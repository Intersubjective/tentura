import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart'
    show PgDateTime, PgTypes, UuidValue;
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts.dart'
    show
        kAvatarPlaceholderUrl,
        kImageExt,
        kImageServer,
        kImagesPath,
        kTitleMaxLength,
        kTitleMinLength;
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/post_summary.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/beacon_media_state.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/beacon_mapper.dart';
import 'post_lock_repository.dart';

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

BeaconEntity _beaconRowToEntity(
  Beacon beacon, {
  required User author,
  List<Image>? images,
}) => beaconModelToEntity(
  beacon,
  author: author,
  images: images,
).copyWith(isDiscoverable: beacon.isDiscoverable);

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
  Future<List<PostSummary>> myPosts(String viewerId) =>
      _postSummaries(viewerId: viewerId);

  @override
  Future<PostSummary?> postSummary({
    required String viewerId,
    required String beaconId,
  }) async => (await _postSummaries(
    viewerId: viewerId,
    beaconId: beaconId,
  )).firstOrNull;

  /// All of the viewer's Post rows, or only [beaconId]'s.
  Future<List<PostSummary>> _postSummaries({
    required String viewerId,
    String? beaconId,
  }) async {
    final rows = await _database
        .customSelect(
          // `post_my_posts` reports a mute's expiry only, which is null both
          // for «no mute» and for «muted for good»; the row tells them apart.
          '''
SELECT posts.*, cover.image_id::text AS root_image_id,
       cover.author_id AS root_image_author_id,
       EXISTS (
         SELECT 1 FROM public.notification_beacon_mute m
         WHERE m.beacon_id = posts.id
           AND m.account_id = \$1
           AND m.muted_until IS NULL
       ) AS muted_forever
FROM public.post_my_posts(\$1) posts
JOIN public.beacon b ON b.id = posts.id
LEFT JOIN LATERAL (
  SELECT i.id AS image_id, i.author_id
  FROM public.beacon_room_message_attachment a
  JOIN public.image i ON i.id = a.image_id
  WHERE a.message_id = b.post_root_message_id AND a.kind = 1
  ORDER BY a.position, a.id
  LIMIT 1
) cover ON true
${beaconId == null ? '' : r'WHERE posts.id = $2'}''',
          variables: [
            Variable<String>(viewerId),
            if (beaconId != null) Variable<String>(beaconId),
          ],
        )
        .get();
    return rows.map((row) {
      DateTime? timestamp(String key) => row
          .readNullableWithType(PgTypes.timestampWithTimezone, key)
          ?.dateTime
          .toUtc();
      final authorId = row.read<String>('author_id');
      final imageId = row.readNullable<String>('author_image_id');
      return PostSummary(
        id: row.read<String>('id'),
        authorId: authorId,
        authorName: row.read<String>('author_name'),
        authorAvatar: imageId == null
            ? kAvatarPlaceholderUrl
            : '$kImageServer/$kImagesPath/$authorId/$imageId.$kImageExt',
        rootImageUrl: row.readNullable<String>('root_image_id') == null
            ? null
            : '$kImageServer/$kImagesPath/${row.read<String>('root_image_author_id')}/${row.read<String>('root_image_id')}.$kImageExt',
        rootExcerpt: row.readNullable<String>('root_excerpt'),
        lastMessageExcerpt: row.readNullable<String>('last_message_excerpt'),
        lastMessageAt: timestamp('last_message_at'),
        lastActivityAt: timestamp('last_activity_at'),
        pinnedAt: timestamp('pinned_at'),
        mutedUntil: timestamp('muted_until'),
        mutedForever: row.read<bool>('muted_forever'),
        unreadCount: row.read<int>('unread_count'),
        isAuthor: row.read<bool>('is_author'),
      );
    }).toList();
  }

  @override
  Future<List<String>> deadlineReminderCandidateIds({
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  }) async {
    final rows = await _database
        .customSelect(
          r'''SELECT id FROM public.beacon WHERE kind = 0 AND status = 0 AND end_at >= $1 AND end_at < $2''',
          variables: [
            Variable(
              PgDateTime(nextUtcDayStart),
              PgTypes.timestampWithTimezone,
            ),
            Variable(
              PgDateTime(followingUtcDayStart),
              PgTypes.timestampWithTimezone,
            ),
          ],
        )
        .get();
    return rows.map((row) => row.read<String>('id')).toList();
  }

  @override
  Future<BeaconEntity?> lockOpenBeaconForDeadlineReminder({
    required String beaconId,
    required DateTime nextUtcDayStart,
    required DateTime followingUtcDayStart,
  }) async {
    final rows = await _database
        .customSelect(
          r'''SELECT id FROM public.beacon WHERE id = $1 AND kind = 0 AND status = 0 AND end_at >= $2 AND end_at < $3 FOR UPDATE''',
          variables: [
            Variable<String>(beaconId),
            Variable(
              PgDateTime(nextUtcDayStart),
              PgTypes.timestampWithTimezone,
            ),
            Variable(
              PgDateTime(followingUtcDayStart),
              PgTypes.timestampWithTimezone,
            ),
          ],
        )
        .get();
    return rows.isEmpty ? null : getBeaconById(beaconId: beaconId);
  }

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
    bool? isDiscoverable,
    BeaconKind kind = BeaconKind.request,
    BeaconForwardPolicyValue forwardPolicy = BeaconForwardPolicyValue.open,
  }) => _database.withMutatingUser(authorId, () async {
    final effectiveStatus = status ?? BeaconStatus.open;
    final publishedAt = effectiveStatus == BeaconStatus.draft
        ? null
        : DateTime.timestamp();
    var beacon = await _database.managers.beacons.createReturning(
      (o) => o(
        userId: Value(authorId),
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
        publishedAt: Value(
          publishedAt == null ? null : PgDateTime(publishedAt),
        ),
        addressLabel: Value(addressLabel),
        lineageParentBeaconId: Value(lineageParentBeaconId),
        lineageRootBeaconId: Value(lineageRootBeaconId),
        isDiscoverable: Value(isDiscoverable ?? true),
        kind: Value(kind.value),
        forwardPolicy: Value(forwardPolicy.value),
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

    return _beaconRowToEntity(
      beacon,
      author: author,
      images: images,
    );
  });

  @override
  Future<BeaconEntity> createChildBeacon({
    required String authorId,
    required String parentBeaconId,
    required String title,
    required String description,
    String? context,
    double? latitude,
    double? longitude,
    DateTime? startAt,
    DateTime? endAt,
    Set<String>? tags,
    Set<String>? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    required bool draft,
  }) => _database.withMutatingUser(authorId, () async {
    final effectiveStatus = draft ? BeaconStatus.draft : BeaconStatus.open;
    final publishedAt = draft ? null : DateTime.timestamp();
    var beacon = await _database.managers.beacons.createReturning(
      (o) => o(
        userId: Value(authorId),
        title: title,
        parentBeaconId: Value(parentBeaconId),
        publishedAt: Value(
          publishedAt == null ? null : PgDateTime(publishedAt),
        ),
        context: Value(_beaconContextForDb(context)),
        description: Value(description),
        lat: Value(latitude),
        long: Value(longitude),
        startAt: Value(startAt == null ? null : PgDateTime(startAt)),
        endAt: Value(endAt == null ? null : PgDateTime(endAt)),
        tags: Value.absentIfNull(tags?.join(',')),
        needs: Value(needs == null || needs.isEmpty ? '' : needs.join(',')),
        primaryNeedSlug: Value(primaryNeedSlug),
        status: Value(effectiveStatus.smallintValue),
        addressLabel: Value(addressLabel),
      ),
    );

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

    return _beaconRowToEntity(
      beacon,
      author: author,
      images: const [],
    );
  });

  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    // Avoid managers.withReferences(...).getSingle(): Drift wraps prefetch in
    // a nested transaction (SAVEPOINT). Over a postgres Pool that can surface
    // as 25P01 CouldNotRollBackException (TENTURA-SERVER-H).
    final beacon = await _database.managers.beacons
        .filter(
          filterByUserId == null
              ? (e) => e.id.equals(beaconId)
              : (e) =>
                    e.id.equals(beaconId) & e.userId.id.equals(filterByUserId),
        )
        .getSingle();

    final images = await _getBeaconImages(beaconId);
    final ownerId = beacon.userId;
    if (ownerId == null) {
      if (beacon.status == BeaconStatus.deleted.smallintValue) {
        throw BeaconStructuralOnlyException(beaconId: beaconId);
      }
      throw IdNotFoundException(
        id: beaconId,
        description: 'Request owner missing for [$beaconId]',
      );
    }

    final authorRow = await _database.managers.users
        .filter((e) => e.id.equals(ownerId))
        .getSingle();

    return _beaconRowToEntity(
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
    bool? isDiscoverable,
    bool isDiscoverableProvided = false,
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
            isDiscoverable: isDiscoverableProvided
                ? Value(isDiscoverable!)
                : const Value.absent(),
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
    bool? isDiscoverable,
    bool isDiscoverableProvided = false,
  }) => _database.withMutatingUser(userId, () async {
    // Serialize editable state transitions before reading the old deadline.
    await _database
        .customSelect(
          r'''SELECT 1 FROM public.beacon WHERE id = $1 AND user_id = $2 FOR UPDATE''',
          variables: [Variable<String>(beaconId), Variable<String>(userId)],
        )
        .get();
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
            isDiscoverable: isDiscoverableProvided
                ? Value(isDiscoverable!)
                : const Value.absent(),
          ),
        );

    return getBeaconById(
      beaconId: beaconId,
      filterByUserId: userId,
    );
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

  // Not a constructor dependency: a DI edge to the lock reorders registration
  // of the singletons that depend on this repository.
  @override
  Future<void> lockPostForMutation(String beaconId) =>
      PostLockRepository(_database).lockForPostMutation(beaconId);

  @override
  Future<void> setForwardPolicy({
    required String beaconId,
    required BeaconForwardPolicyValue policy,
  }) async {
    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update((o) => o(forwardPolicy: Value(policy.value)));
  }

  @override
  Future<void> convertPostToRequest({
    required String beaconId,
    required String title,
    required String description,
    required Set<String>? needs,
    required String? primaryNeedSlug,
    required DateTime? startAt,
    required DateTime? endAt,
    required bool isDiscoverable,
  }) async {
    final updated = await _database.customUpdate(
      r'''
UPDATE public.beacon
SET title = $2, description = $3, needs = $4, primary_need_slug = $5,
    start_at = $6, end_at = $7, kind = 0, forward_policy = 1,
    is_discoverable = $8, updated_at = now()
WHERE id = $1 AND kind = 1 AND status = 0
''',
      variables: [
        Variable<String>(beaconId),
        Variable<String>(title),
        Variable<String>(description),
        Variable<String>(needs == null || needs.isEmpty ? '' : needs.join(',')),
        Variable<String>(primaryNeedSlug),
        Variable<PgDateTime>(
          startAt == null ? null : PgDateTime(startAt.toUtc()),
          PgTypes.timestampWithTimezone,
        ),
        Variable<PgDateTime>(
          endAt == null ? null : PgDateTime(endAt.toUtc()),
          PgTypes.timestampWithTimezone,
        ),
        Variable<bool>(isDiscoverable),
      ],
    );
    if (updated != 1) {
      throw const BeaconCreateException(description: 'Not an open Post');
    }
  }

  @override
  Future<void> postConvertedToRequestMessage(String beaconId) =>
      _database.customInsert(
        r'''
INSERT INTO public.beacon_room_message
  (beacon_id, body, system_message_kind, system_payload)
VALUES ($1, '', $2, $3::jsonb)
''',
        variables: [
          Variable<String>(beaconId),
          Variable<int>(BeaconRoomSystemMessageKind.convertedToRequest),
          Variable<String>('{"event":"convertedToRequest"}'),
        ],
      );

  @override
  Future<void> setPostRootMessage({
    required String beaconId,
    required String messageId,
  }) => _database.customStatement(
    'UPDATE public.beacon SET post_root_message_id = \$2 '
    'WHERE id = \$1 AND post_root_message_id IS NULL',
    [beaconId, messageId],
  );

  @override
  Future<bool> isPostAddressee({
    required String beaconId,
    required String userId,
  }) async {
    final rows = await _database
        .customSelect(
          r'SELECT 1 FROM public.beacon_participant bp '
          r'JOIN public.beacon b ON b.id = bp.beacon_id '
          r'WHERE bp.beacon_id = $1 AND bp.user_id = $2 AND bp.role = 6 '
          r'AND b.user_id <> bp.user_id',
          variables: [Variable<String>(beaconId), Variable<String>(userId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<void> leavePostAsAddressee({
    required String beaconId,
    required String userId,
  }) async {
    await _database.customStatement(
      r'UPDATE public.inbox_item SET status = 2 '
      r'WHERE beacon_id = $1 AND user_id = $2',
      [beaconId, userId],
    );
    await _database.customStatement(
      r'UPDATE public.beacon_participant '
      r'SET room_access = 5, updated_at = now() '
      r'WHERE beacon_id = $1 AND user_id = $2',
      [beaconId, userId],
    );
  }

  @override
  Future<void> returnToPostAsAddressee({
    required String beaconId,
    required String userId,
  }) async {
    await _database.customStatement(
      r'UPDATE public.inbox_item SET status = 1 '
      r'WHERE beacon_id = $1 AND user_id = $2',
      [beaconId, userId],
    );
    await _database.customStatement(
      r'UPDATE public.beacon_participant '
      r'SET room_access = 0, updated_at = now() '
      r'WHERE beacon_id = $1 AND user_id = $2',
      [beaconId, userId],
    );
    await _database.customStatement(
      r'SELECT public.post_reconcile_admission($1, $2)',
      [beaconId, userId],
    );
    // `post_reconcile_admission` ignores a Request converted from a Post.
    await _database.customStatement(
      r'UPDATE public.beacon_participant SET room_access = 3, updated_at = now() '
      r'WHERE beacon_id = $1 AND user_id = $2 '
      r'AND EXISTS (SELECT 1 FROM public.beacon WHERE id = $1 AND kind = 0)',
      [beaconId, userId],
    );
  }

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

      final publishedAt = DateTime.timestamp();
      await _database.managers.beacons
          .filter((e) => e.id.equals(id))
          .update(
            (o) => o(
              status: Value(BeaconStatus.open.smallintValue),
              statusChangedAt: Value(PgDateTime(publishedAt)),
              publishedAt: Value(PgDateTime(publishedAt)),
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

  @override
  Future<BeaconEntity> publishChildDraft({
    required String childBeaconId,
    required String actorId,
  }) => _database.withMutatingUser(actorId, () async {
    return _database.transaction(() async {
      final existing = await _database.managers.beacons
          .filter(
            (e) => e.id.equals(childBeaconId) & e.userId.id.equals(actorId),
          )
          .getSingleOrNull();

      if (existing == null) {
        throw const BeaconCreateException(
          description: 'Request not found or not owned',
        );
      }

      if (existing.status != BeaconStatus.draft.smallintValue) {
        return getBeaconById(beaconId: childBeaconId, filterByUserId: actorId);
      }

      final publishedAt = DateTime.timestamp();
      await _database.managers.beacons
          .filter((e) => e.id.equals(childBeaconId))
          .update(
            (o) => o(
              status: Value(BeaconStatus.open.smallintValue),
              statusChangedAt: Value(PgDateTime(publishedAt)),
              publishedAt: Value(PgDateTime(publishedAt)),
            ),
          );

      await _insertBeaconPublishedEvent(
        beaconId: childBeaconId,
        actorId: actorId,
        title: existing.title,
      );

      return getBeaconById(beaconId: childBeaconId, filterByUserId: actorId);
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
  Future<void> deleteStage({required String imageId}) => _database
      .managers
      .beaconImageStages
      .filter((e) => e.imageId.id(UuidValue.fromString(imageId)))
      .delete();

  @override
  Future<void> setCover({
    required String beaconId,
    required String? coverImageId,
    required BeaconCoverSource coverSource,
  }) => _database.managers.beacons
      .filter((e) => e.id.equals(beaconId))
      .update(
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
    final currentAttachedIds =
        (await _database.managers.beaconImages
                .filter((e) => e.beaconId.id.equals(beaconId))
                .get())
            .map((e) => e.imageId.uuid)
            .toSet();
    final currentStagedIds =
        (await _database.managers.beaconImageStages
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

    await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .update(
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
