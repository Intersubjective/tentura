import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../service/fcm_service.dart';
import 'fcm_remote_repository.dart';
import 'mock/fcm_remote_repository_mock.dart';

/// Dev/prod FCM delivery: real Firebase HTTP when service-account creds are set;
/// mock with a startup warning when any of the three server vars is missing.
/// The test environment keeps [FcmRemoteRepositoryMock] via its own annotation.
@module
abstract class FcmRemoteRepositoryModule {
  @Singleton(
    env: [Environment.dev, Environment.prod],
    order: 1,
  )
  FcmRemoteRepositoryPort fcmRemoteRepository(
    Env env,
    FcmService fcmService,
    FcmTokenRepositoryPort fcmTokenRepository,
    Logger logger,
  ) {
    if (!env.isFcmConfigured) {
      logger.warning(
        '[FCM] Push mocking enabled — missing server Firebase creds: '
        '${env.missingFcmServerCreds.join(', ')}. '
        'Set all three for real FCM HTTP.',
      );
      return FcmRemoteRepositoryMock(logger);
    }
    return FcmRemoteRepository(
      env,
      fcmService,
      fcmTokenRepository,
      logger,
    );
  }
}
