import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/use_case/fcm_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  test('deleteToken calls deleteByUserAndApp', () async {
    final repo = FakeFcmTokenRepository();
    final case_ = FcmCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('test'),
    );

    final ok = await case_.deleteToken(
      userId: 'U1',
      appId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    );

    expect(ok, isTrue);
    expect(repo.deleted, [
      (userId: 'U1', appId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
    ]);
  });
}

class FakeFcmTokenRepository implements FcmTokenRepositoryPort {
  final deleted = <({String userId, String appId})>[];

  @override
  Future<void> deleteByUserAndApp({
    required String userId,
    required String appId,
  }) async {
    deleted.add((userId: userId, appId: appId));
  }

  @override
  Future<void> deleteToken(String token) async {}

  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async => [];

  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {}
}
