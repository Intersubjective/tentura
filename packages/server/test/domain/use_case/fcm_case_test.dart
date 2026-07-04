import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:uuid/uuid.dart';

import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/use_case/fcm_case.dart';
import 'package:tentura_server/domain/util/debug_send_rate_limiter.dart';
import 'package:tentura_server/env.dart';

void main() {
  late FakeFcmTokenRepository repo;
  late FakeFcmRemote remote;
  late DebugSendRateLimiter limiter;
  late FcmCase case_;
  late Env env;

  setUp(() {
    repo = FakeFcmTokenRepository();
    remote = FakeFcmRemote();
    limiter = DebugSendRateLimiter();
    env = Env(environment: Environment.test);
    case_ = FcmCase(
      repo,
      remote,
      limiter,
      env: env,
      logger: Logger('test'),
    );
  });

  test('deleteToken calls deleteByUserAndApp', () async {
    final ok = await case_.deleteToken(
      userId: 'U1',
      appId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    );

    expect(ok, isTrue);
    expect(repo.deleted, [
      (userId: 'U1', appId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
    ]);
  });

  test('sendTestNotification returns no_devices when empty', () async {
    final result = await case_.sendTestNotification(userId: 'U1');

    expect(result['ok'], isFalse);
    expect(result['reason'], 'no_devices');
    expect(remote.sentTokens, isEmpty);
  });

  test('sendTestNotification sends to all tokens', () async {
    repo.tokensByUser['U1'] = [
      FcmTokenEntity(
        userId: 'U1',
        appId: const Uuid().v4obj(),
        token: 'tok-1',
        platform: 'web',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
      FcmTokenEntity(
        userId: 'U1',
        appId: const Uuid().v4obj(),
        token: 'tok-2',
        platform: 'android',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
    ];

    final result = await case_.sendTestNotification(userId: 'U1');

    expect(result['ok'], isTrue);
    expect(result['devices'], 2);
    expect(result['sent'], 2);
    expect(remote.sentTokens, {'tok-1', 'tok-2'});
  });

  test('sendTestNotification counts stale tokens', () async {
    repo.tokensByUser['U1'] = [
      FcmTokenEntity(
        userId: 'U1',
        appId: const Uuid().v4obj(),
        token: 'dead',
        platform: 'web',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
      FcmTokenEntity(
        userId: 'U1',
        appId: const Uuid().v4obj(),
        token: 'live',
        platform: 'android',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
    ];
    remote.staleTokens.add('dead');

    final result = await case_.sendTestNotification(userId: 'U1');

    expect(result['ok'], isTrue);
    expect(result['devices'], 2);
    expect(result['sent'], 1);
  });

  test(
    'sendTestNotification counts any send failure, not just stale tokens',
    () async {
      repo.tokensByUser['U1'] = [
        FcmTokenEntity(
          userId: 'U1',
          appId: const Uuid().v4obj(),
          token: 'firefox-token',
          platform: 'web',
          createdAt: DateTime.utc(2026),
          lastRefreshedAt: DateTime.utc(2026),
        ),
        FcmTokenEntity(
          userId: 'U1',
          appId: const Uuid().v4obj(),
          token: 'chrome-token',
          platform: 'web',
          createdAt: DateTime.utc(2026),
          lastRefreshedAt: DateTime.utc(2026),
        ),
      ];
      remote.rejectedTokens.add('firefox-token');

      final result = await case_.sendTestNotification(userId: 'U1');

      expect(result['ok'], isTrue);
      expect(result['devices'], 2);
      expect(result['sent'], 1);
    },
  );

  test('sendTestNotification is rate limited', () async {
    repo.tokensByUser['U1'] = [
      FcmTokenEntity(
        userId: 'U1',
        appId: const Uuid().v4obj(),
        token: 'tok-1',
        platform: 'web',
        createdAt: DateTime.utc(2026),
        lastRefreshedAt: DateTime.utc(2026),
      ),
    ];

    await case_.sendTestNotification(userId: 'U1');
    final result = await case_.sendTestNotification(userId: 'U1');

    expect(result['ok'], isFalse);
    expect(result['reason'], 'rate_limited');
    expect(remote.sentTokens.length, 1);
  });
}

class FakeFcmTokenRepository implements FcmTokenRepositoryPort {
  final deleted = <({String userId, String appId})>[];
  final tokensByUser = <String, List<FcmTokenEntity>>{};

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
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      tokensByUser[userId] ?? [];

  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {}
}

class FakeFcmRemote implements FcmRemoteRepositoryPort {
  final sentTokens = <String>{};
  final staleTokens = <String>{};
  final rejectedTokens = <String>{};

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    final errors = <Exception>[];
    for (final token in fcmTokens) {
      sentTokens.add(token);
      if (staleTokens.contains(token)) {
        errors.add(FcmTokenNotFoundException(token: token));
      } else if (rejectedTokens.contains(token)) {
        errors.add(
          FcmMessageRejectedException(
            token: token,
            errorCode: 'THIRD_PARTY_AUTH_ERROR',
          ),
        );
      }
    }
    return errors;
  }
}
