import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/data/service/firebase_client_config.dart';
import 'package:tentura/data/service/service_base.dart';

import '../../domain/entity/notification_permissions.dart';
import '../../fcm_debug_log.dart';

@singleton
class FcmService extends ServiceBase {
  const FcmService._({
    required super.env,
    required super.logger,
  });

  @factoryMethod
  factory FcmService.create({
    required Env env,
    required Logger logger,
  }) {
    logFirebaseClientConfig(env);
    if (!isFirebaseClientConfigValid(env)) {
      logger.info('Firebase Messaging configured with fake service');
      fcmLog(
        'FcmService: using fake — ${firebaseClientConfigIssue(env) ?? 'FB_API_KEY empty'}',
      );
      return const _FcmServiceFake();
    }
    fcmLog('FcmService: real Firebase Messaging');
    return FcmService._(
      env: env,
      logger: logger,
    );
  }

  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  //
  //
  Future<NotificationPermissions> requestPermission() async {
    fcmLog('FcmService: requestPermission (Firebase)');
    final settings = await FirebaseMessaging.instance.requestPermission(
      provisional: true,
    );
    final status = settings.authorizationStatus;
    fcmLog(
      'FcmService: authorizationStatus=${status.name} '
      'alert=${settings.alert} badge=${settings.badge}',
    );
    return NotificationPermissions(
      authorized: status == AuthorizationStatus.authorized,
    );
  }

  //
  //
  Future<String?> getToken() async {
    fcmLog(
      'FcmService: getToken vapidKeyLen=${env.firebaseVapidKey.length}',
    );
    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: env.firebaseVapidKey,
    );
    fcmLog('FcmService: getToken result ${fcmTokenFingerprint(token)}');
    return token;
  }
}

final class _FcmServiceFake implements FcmService {
  const _FcmServiceFake();

  @override
  Env get env => throw UnimplementedError();

  @override
  Logger get logger => throw UnimplementedError();

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<String?> getToken() {
    fcmLog('FcmService: fake getToken → null');
    return Future.value();
  }

  @override
  Future<NotificationPermissions> requestPermission() {
    fcmLog(
      'FcmService: fake requestPermission → authorized=false '
      '(set FB_API_KEY / other FB_* dart-defines)',
    );
    return Future.value(
      const NotificationPermissions(),
    );
  }
}
