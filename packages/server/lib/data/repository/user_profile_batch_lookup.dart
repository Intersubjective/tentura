import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/user_mapper.dart';
import '../mapper/user_presence_mapper.dart';

/// Batch-friendly user profile reads (display fields, public GraphQL shape).
abstract interface class UserProfileBatchLookup {
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids);

  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
  });
}

@LazySingleton(as: UserProfileBatchLookup)
class DriftUserProfileBatchLookup implements UserProfileBatchLookup {
  DriftUserProfileBatchLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(Iterable<String> ids) async {
    final idList = _distinctNonEmptyIds(ids);
    if (idList.isEmpty) {
      return {};
    }

    final users =
        await _database.managers.users.filter((u) => u.id.isIn(idList)).get();
    return {for (final u in users) u.id: userModelToEntity(u)};
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
  }) async {
    final idList = _distinctNonEmptyIds(ids);
    if (idList.isEmpty) {
      return {};
    }

    final users =
        await _database.managers.users.filter((u) => u.id.isIn(idList)).get();
    if (users.isEmpty) {
      return {};
    }

    final imageByUuid = await _imagesByUuidForUsers(users);
    final presenceByUserId = await _presenceByUserId(idList);

    return {
      for (final user in users)
        user.id: _userPublicRecord(
          user: user,
          image: user.imageId != null ? imageByUuid[user.imageId] : null,
          isMutualFriend: reciprocalPeerIds.contains(user.id),
          presence: presenceByUserId[user.id],
        ),
    };
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
    final rows = await (_database.select(_database.userPresence)
          ..where((t) => t.userId.isIn(userIds)))
        .get();
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
    required UserPresenceRecord? presence,
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
      isMutualFriend: isMutualFriend,
      image: imageRecord,
      userPresence: presence,
    );
  }

  static List<String> _distinctNonEmptyIds(Iterable<String> ids) =>
      ids.where((id) => id.isNotEmpty).toSet().toList();
}
