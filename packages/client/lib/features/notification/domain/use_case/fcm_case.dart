import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

import '../port/fcm_local_repository_port.dart';
import '../port/fcm_remote_repository_port.dart';
import '../entity/notification_permissions.dart';
import '../fcm_debug_log.dart';

@singleton
class FcmCase {
  FcmCase(
    this._fcmLocalRepository,
    this._fcmRemoteRepository,
    this._authLocalRepository,
    this._settingsRepository,
  );

  final FcmLocalRepositoryPort _fcmLocalRepository;

  final FcmRemoteRepositoryPort _fcmRemoteRepository;

  final AuthLocalRepositoryPort _authLocalRepository;

  final SettingsRepositoryPort _settingsRepository;

  Stream<String> get onTokenRefresh => _fcmLocalRepository.onTokenRefresh;

  Stream<String> get currentAccountChanges =>
      _authLocalRepository.currentAccountChanges();

  ///
  Future<NotificationPermissions> requestPermission() {
    fcmLog('FcmCase: requestPermission');
    return _fcmLocalRepository.requestPermission();
  }

  ///
  Future<bool> checkIfRegistrationNeeded() async {
    final fcmLastRegistrationAt =
        (await _authLocalRepository.getCurrentAccount())?.fcmTokenUpdatedAt;
    final needed = fcmLastRegistrationAt == null ||
        fcmLastRegistrationAt
            .add(const Duration(days: 30))
            .isBefore(DateTime.timestamp());
    fcmLog(
      'FcmCase: checkIfRegistrationNeeded=$needed '
      'lastRegisteredAt=$fcmLastRegistrationAt',
    );
    return needed;
  }

  ///
  Future<String> registerFcmToken({
    required String platform,
    String? token,
  }) async {
    fcmLog('FcmCase: registerFcmToken platform=$platform');
    token ??=
        await _fcmLocalRepository.getToken() ??
        (throw Exception('[FcmCase] No FCM token!'));
    fcmLog('FcmCase: token ${fcmTokenFingerprint(token)}');

    var appId = await _settingsRepository.getAppId();

    if (appId == null) {
      appId = const Uuid().v4();
      await _settingsRepository.setAppId(appId);
      fcmLog('FcmCase: created new appId=$appId');
    } else {
      fcmLog('FcmCase: reusing appId=$appId');
    }

    fcmLog('FcmCase: calling server fcmTokenRegister');
    await _fcmRemoteRepository.registerToken(
      appId: appId,
      token: token,
      platform: platform,
    );
    fcmLog('FcmCase: server fcmTokenRegister OK');

    final currentAccount = await _authLocalRepository.getCurrentAccount();
    if (currentAccount == null) {
      throw Exception('[FcmCase] No current account!');
    }
    await _authLocalRepository.updateAccount(
      currentAccount.copyWith(
        fcmTokenUpdatedAt: DateTime.timestamp(),
      ),
    );
    fcmLog('FcmCase: updated local fcmTokenUpdatedAt');
    return appId;
  }
}
