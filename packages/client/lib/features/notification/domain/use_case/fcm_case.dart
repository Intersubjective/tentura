import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

import '../entity/fcm_registration_info.dart';
import '../entity/fcm_test_send_result.dart';
import '../entity/last_fcm_registration.dart';
import '../port/fcm_local_repository_port.dart';
import '../port/fcm_remote_repository_port.dart';
import '../entity/notification_permissions.dart';
import 'package:tentura/features/notification/fcm_debug_log.dart';

@singleton
class FcmCase {
  FcmCase(
    this._fcmLocalRepository,
    this._fcmRemoteRepository,
    this._settingsRepository,
  );

  final FcmLocalRepositoryPort _fcmLocalRepository;

  final FcmRemoteRepositoryPort _fcmRemoteRepository;

  final SettingsRepositoryPort _settingsRepository;

  Stream<String> get onTokenRefresh => _fcmLocalRepository.onTokenRefresh;

  ///
  Future<NotificationPermissions> requestPermission() {
    fcmLog('FcmCase: requestPermission');
    return _fcmLocalRepository.requestPermission();
  }

  ///
  /// Syncs the device FCM token for [accountId]. When [forceRegister] is true
  /// (e.g. [onTokenRefresh]), always posts to the server.
  Future<String?> syncTokenForAccount({
    required String accountId,
    required String platform,
    String? token,
    bool forceRegister = false,
  }) async {
    fcmLog(
      'FcmCase: syncTokenForAccount accountId=$accountId '
      'forceRegister=$forceRegister',
    );
    token ??= await _fcmLocalRepository.getToken();
    if (token == null || token.isEmpty) {
      fcmLog('FcmCase: no FCM token from platform');
      return null;
    }
    fcmLog('FcmCase: token ${fcmTokenFingerprint(token)}');

    final appId = await _ensureAppId();

    if (!forceRegister) {
      final last = await _settingsRepository.getLastFcmRegistration();
      if (last != null &&
          last.matches(
            accountId: accountId,
            appId: appId,
            token: token,
          )) {
        fcmLog('FcmCase: registration unchanged, skip server call');
        return appId;
      }
    }

    fcmLog('FcmCase: calling server fcmTokenRegister');
    await _fcmRemoteRepository.registerToken(
      appId: appId,
      token: token,
      platform: platform,
    );
    fcmLog('FcmCase: server fcmTokenRegister OK');

    await _settingsRepository.setLastFcmRegistration(
      LastFcmRegistration(
        accountId: accountId,
        appId: appId,
        token: token,
      ),
    );
    fcmLog('FcmCase: updated LastFcmRegistration');
    return appId;
  }

  ///
  /// Best-effort: removes this device's row on the server. Must not throw.
  Future<void> unregisterCurrentDevice() async {
    final appId = await _settingsRepository.getAppId();
    if (appId == null) {
      fcmLog('FcmCase: unregister skipped (no appId)');
      return;
    }
    try {
      fcmLog('FcmCase: fcmTokenDelete appId=$appId');
      await _fcmRemoteRepository.deleteToken(appId: appId);
      fcmLog('FcmCase: fcmTokenDelete OK');
    } catch (e, st) {
      fcmLog('FcmCase: unregister failed (ignored): $e');
      fcmLog('FcmCase: stack: $st');
    }
    await _settingsRepository.setLastFcmRegistration(null);
  }

  Future<FcmRegistrationInfo> getRegistrationInfo({
    required String accountId,
    required bool permissionGranted,
    required String platform,
  }) async {
    final token = await _fcmLocalRepository.getToken();
    final appId = await _settingsRepository.getAppId();
    final last = await _settingsRepository.getLastFcmRegistration();
    final serverSynced = token != null &&
        token.isNotEmpty &&
        appId != null &&
        (last?.matches(
              accountId: accountId,
              appId: appId,
              token: token,
            ) ??
            false);
    return FcmRegistrationInfo(
      token: token,
      appId: appId,
      platform: platform,
      permissionGranted: permissionGranted,
      serverSynced: serverSynced,
    );
  }

  Future<FcmTestSendResult> sendTestNotification() =>
      _fcmRemoteRepository.sendTestNotification();

  Future<String> _ensureAppId() async {
    var appId = await _settingsRepository.getAppId();
    if (appId == null) {
      appId = const Uuid().v4();
      await _settingsRepository.setAppId(appId);
      fcmLog('FcmCase: created new appId=$appId');
    } else {
      fcmLog('FcmCase: reusing appId=$appId');
    }
    return appId;
  }
}
