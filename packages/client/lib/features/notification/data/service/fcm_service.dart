import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/data/service/service_base.dart';

import '../../domain/entity/notification_permissions.dart';

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
    if (env.firebaseApiKey.isEmpty) {
      logger.info('Firebase Messaging configured with fake service');
      return const _FcmServiceFake();
    }
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
    final settings = await FirebaseMessaging.instance.requestPermission(
      provisional: true,
    );
    return NotificationPermissions(
      authorized:
          settings.authorizationStatus == AuthorizationStatus.authorized,
    );
  }

  //
  //
  Future<String?> getToken() =>
      FirebaseMessaging.instance.getToken(vapidKey: env.firebaseVapidKey);
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
  Future<String?> getToken() => Future.value();

  @override
  Future<NotificationPermissions> requestPermission() => Future.value(
    const NotificationPermissions(),
  );
}
