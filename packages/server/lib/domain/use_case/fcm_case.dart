import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

import 'package:tentura_server/domain/util/debug_send_rate_limiter.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class FcmCase extends UseCaseBase {
  FcmCase(
    this._fcmTokenRepository,
    this._fcmRemote,
    this._rateLimiter, {
    required super.env,
    required super.logger,
  });

  final FcmTokenRepositoryPort _fcmTokenRepository;

  final FcmRemoteRepositoryPort _fcmRemote;

  final DebugSendRateLimiter _rateLimiter;

  static const _testTitle = 'Tentura test';

  static const _testBody = 'Push notifications are working.';

  Future<bool> registerToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {
    if (userId.isEmpty || appId.isEmpty || token.isEmpty || platform.isEmpty) {
      return false;
    }
    try {
      await _fcmTokenRepository.putToken(
        userId: userId,
        appId: appId,
        token: token,
        platform: platform,
      );
      logger.info(
        '[FCM] fcmTokenRegister stored userId=$userId platform=$platform '
        'appId=$appId tokenLen=${token.length}',
      );
      return true;
    } catch (e, st) {
      logger.warning('[FCM] fcmTokenRegister failed userId=$userId: $e', e, st);
      return false;
    }
  }

  Future<bool> deleteToken({
    required String userId,
    required String appId,
  }) async {
    if (userId.isEmpty || appId.isEmpty) {
      return false;
    }
    try {
      await _fcmTokenRepository.deleteByUserAndApp(
        userId: userId,
        appId: appId,
      );
      logger.info(
        '[FCM] fcmTokenDelete userId=$userId appId=$appId',
      );
      return true;
    } catch (e, st) {
      logger.warning('[FCM] fcmTokenDelete failed userId=$userId: $e', e, st);
      return false;
    }
  }

  Future<Map<String, Object?>> sendTestNotification({
    required String userId,
  }) async {
    if (!_rateLimiter.tryAcquire(userId, DebugSendChannel.fcm)) {
      return _fcmTestResult(
        ok: false,
        devices: 0,
        sent: 0,
        reason: 'rate_limited',
      );
    }

    final rows = await _fcmTokenRepository.getTokensByUserId(userId);
    final tokenList = rows.toList();
    if (tokenList.isEmpty) {
      return _fcmTestResult(
        ok: false,
        devices: 0,
        sent: 0,
        reason: 'no_devices',
      );
    }

    final fcmTokens = tokenList.map((FcmTokenEntity e) => e.token).toSet();
    final message = const FcmNotificationEntity(
      title: _testTitle,
      body: _testBody,
    );

    final results = await _fcmRemote.sendChatNotification(
      fcmTokens: fcmTokens,
      message: message,
    );

    final staleTokens = results.whereType<FcmTokenNotFoundException>().length;
    final sent = fcmTokens.length - staleTokens;

    return _fcmTestResult(
      ok: true,
      devices: fcmTokens.length,
      sent: sent,
      mock: !env.isFcmConfigured,
    );
  }

  Map<String, Object?> _fcmTestResult({
    required bool ok,
    required int devices,
    required int sent,
    bool mock = false,
    String? reason,
  }) => {
    'ok': ok,
    'devices': devices,
    'sent': sent,
    'mock': mock,
    if (reason != null) 'reason': reason,
  };
}
