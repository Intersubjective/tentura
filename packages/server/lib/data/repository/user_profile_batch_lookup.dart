import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_availability_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart';
import '../mapper/user_availability_mapper.dart';
import '../mapper/user_mapper.dart';
import '../mapper/user_presence_mapper.dart';
import 'constellation_field_repository.dart' show readCustomSelectTimestamptz;

@LazySingleton(as: UserProfileBatchLookup)
class DriftUserProfileBatchLookup implements UserProfileBatchLookup {
  DriftUserProfileBatchLookup(
    this._database,
    this._userAvailabilityRepository,
  );

  final TenturaDb _database;

  final UserAvailabilityRepositoryPort _userAvailabilityRepository;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final idList = _distinctNonEmptyIds(ids);
    if (idList.isEmpty) {
      return {};
    }

    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    return {for (final u in users) u.id: userModelToEntity(u)};
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    final idList = _distinctNonEmptyIds(ids);
    if (idList.isEmpty) {
      return {};
    }

    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    if (users.isEmpty) {
      return {};
    }

    final imageByUuid = await _imagesByUuidForUsers(users);
    final presenceByUserId = await _presenceByUserId(idList);
    final todayUtc = publicUserAvailabilityTodayUtc();
    final availabilityEntities = await _userAvailabilityRepository.fetchByUserIds(
      idList.toSet(),
    );

    final overlayTrustAndScores =
        viewerTrustsPeerIds.isNotEmpty || scoresByPeerId.isNotEmpty;

    return {
      for (final user in users)
        user.id: _userPublicRecord(
          user: user,
          image: user.imageId != null ? imageByUuid[user.imageId] : null,
          isMutualFriend: reciprocalPeerIds.contains(user.id),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(user.id),
          myVote: overlayTrustAndScores
              ? (viewerTrustsPeerIds.contains(user.id) ? 1 : 0)
              : null,
          scores: [
            ?scoresByPeerId[user.id],
          ],
          presence: presenceByUserId[user.id],
          userAvailability: userAvailabilityEntityToPublicRecord(
            entity: availabilityEntities[user.id],
            todayUtc: todayUtc,
          ),
        ),
    };
  }

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async {
    final idList = _distinctNonEmptyIds(ids)..sort();
    if (idList.isEmpty) {
      return {};
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT
  u.id,
  u.display_name,
  u.handle,
  i.id::text AS image_id,
  i.hash AS image_hash,
  i.height AS image_height,
  i.width AS image_width,
  i.author_id AS image_author_id,
  i.created_at AS image_created_at
FROM public."user" u
LEFT JOIN public.image i ON i.id = u.image_id
WHERE u.id = ANY($1::text[])
''',
          variables: [Variable(TypedValue(Type.textArray, idList))],
        )
        .get();

    return {
      for (final row in rows)
        row.read<String>('id'): _constellationPeer(row),
    };
  }

  static ConstellationPeerRecord _constellationPeer(QueryRow row) {
    final imageId = row.readNullable<String>('image_id');
    final handle = (row.readNullable<String>('handle') ?? '').trim();
    return ConstellationPeerRecord(
      id: row.read<String>('id'),
      displayName: row.read<String>('display_name'),
      handle: handle.isEmpty ? null : handle,
      image: imageId == null
          ? null
          : ImagePublicRecord(
              id: imageId,
              hash: row.read<String>('image_hash'),
              height: row.read<int>('image_height'),
              width: row.read<int>('image_width'),
              authorId: row.read<String>('image_author_id'),
              createdAt: readCustomSelectTimestamptz(
                row.data['image_created_at'],
              )!,
            ),
    );
  }

  Future<Map<UuidValue, Image>> _imagesByUuidForUsers(List<User> users) async {
    final imageUuidIds = {
      for (final user in users)
        if (user.imageId case final UuidValue id) id,
    }.toList();
    if (imageUuidIds.isEmpty) {
      return {};
    }

    final images = await _database.managers.images
        .filter((i) => i.id.isIn(imageUuidIds))
        .get();
    return {for (final image in images) image.id: image};
  }

  Future<Map<String, UserPresenceRecord?>> _presenceByUserId(
    List<String> userIds,
  ) async {
    final rows = await (_database.select(
      _database.userPresence,
    )..where((t) => t.userId.isIn(userIds))).get();
    return {
      for (final row in rows)
        row.userId: () {
          final entity = userPresenceModelToEntity(row);
          return UserPresenceRecord(
            lastSeenAt: entity.lastSeenAt,
            status: entity.status.index,
          );
        }(),
    };
  }

  static UserPublicRecord _userPublicRecord({
    required User user,
    required Image? image,
    required bool isMutualFriend,
    required bool subjectExplicitlyTrustsViewer,
    required int? myVote,
    required List<MutualScoreRecord> scores,
    required UserPresenceRecord? presence,
    required UserAvailabilityRecord? userAvailability,
  }) {
    ImagePublicRecord? imageRecord;
    if (image != null) {
      imageRecord = ImagePublicRecord(
        id: image.id.toString(),
        hash: image.hash,
        height: image.height,
        width: image.width,
        authorId: image.authorId,
        createdAt: image.createdAt.dateTime.toUtc(),
      );
    }

    return UserPublicRecord(
      id: user.id,
      displayName: user.displayName,
      description: user.description,
      handle: (user.handle ?? '').trim().isEmpty ? null : user.handle!.trim(),
      myVote: myVote,
      isMutualFriend: isMutualFriend,
      subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
      image: imageRecord,
      scores: scores,
      userPresence: presence,
      userAvailability: userAvailability,
    );
  }

  static List<String> _distinctNonEmptyIds(Iterable<String> ids) =>
      ids.where((id) => id.isNotEmpty).toSet().toList();
}
