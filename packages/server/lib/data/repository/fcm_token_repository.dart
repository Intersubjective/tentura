import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

import '../database/tentura_db.dart';
import '../mapper/fcm_token_mapper.dart';

@Injectable(
  as: FcmTokenRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class FcmTokenRepository implements FcmTokenRepositoryPort {
  const FcmTokenRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async {
    final tokens = await _database.managers.fcmTokens
        .filter((f) => f.userId.id(userId))
        .get(distinct: true);
    return tokens.map(fcmTokenModelToEntity);
  }

  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {
    final appUuid = UuidValue.fromString(appId);
    final refreshedAt = PgDateTime(DateTime.timestamp());

    await _database.transaction(() async {
      await _database.into(_database.fcmTokens).insert(
        FcmTokensCompanion.insert(
          userId: userId,
          appId: appUuid,
          token: token,
          platform: platform,
          lastRefreshedAt: Value(refreshedAt),
        ),
        onConflict: DoUpdate(
          (_) => FcmTokensCompanion(
            token: Value(token),
            platform: Value(platform),
            lastRefreshedAt: Value(refreshedAt),
          ),
        ),
      );

      await _database.customStatement(
        'DELETE FROM fcm_token WHERE token = ? '
        'AND NOT (user_id = ? AND app_id = ?::uuid)',
        [token, userId, appId],
      );
    });
  }

  @override
  Future<void> deleteToken(String token) =>
      _database.managers.fcmTokens.filter((f) => f.token(token)).delete();

  @override
  Future<void> deleteByUserAndApp({
    required String userId,
    required String appId,
  }) =>
      _database.managers.fcmTokens
          .filter(
            (f) => f.userId.id(userId) & f.appId(UuidValue.fromString(appId)),
          )
          .delete();
}
