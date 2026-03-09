import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/domain/entity/fcm_token_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/fcm_token_mapper.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class FcmTokenRepository {
  const FcmTokenRepository(this._database);

  final TenturaDb _database;

  ///
  ///
  ///
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async {
    final tokens = await _database.managers.fcmTokens
        .filter((f) => f.userId.id(userId))
        .get(distinct: true);
    return tokens.map(fcmTokenModelToEntity);
  }

  ///
  /// Insert token into DB, ignore if exists
  ///
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) => _database.managers.fcmTokens.create(
    (o) => o(
      userId: userId,
      appId: UuidValue.fromString(appId),
      token: token,
      platform: platform,
    ),
    mode: InsertMode.insertOrIgnore,
  );

  Future<void> deleteToken(String token) =>
      _database.managers.fcmTokens.filter((f) => f.token(token)).delete();
}
