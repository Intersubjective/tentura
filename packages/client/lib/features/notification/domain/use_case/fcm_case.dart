import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

import '../port/fcm_local_repository_port.dart';
import '../port/fcm_remote_repository_port.dart';
import '../entity/notification_permissions.dart';

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
  Future<NotificationPermissions> requestPermission() =>
      _fcmLocalRepository.requestPermission();

  ///
  Future<bool> checkIfRegistrationNeeded() async {
    final fcmLastRegistrationAt =
        (await _authLocalRepository.getCurrentAccount())?.fcmTokenUpdatedAt;
    return fcmLastRegistrationAt == null ||
        fcmLastRegistrationAt
            .add(const Duration(days: 30))
            .isBefore(DateTime.timestamp());
  }

  ///
  Future<String> registerFcmToken({
    required String platform,
    String? token,
  }) async {
    token ??=
        await _fcmLocalRepository.getToken() ??
        (throw Exception('[FcmCase] No FCM token!'));
    var appId = await _settingsRepository.getAppId();

    if (appId == null) {
      appId = const Uuid().v4();
      await _settingsRepository.setAppId(appId);
    }

    await _fcmRemoteRepository.registerToken(
      appId: appId,
      token: token,
      platform: platform,
    );

    final currentAccount = await _authLocalRepository.getCurrentAccount();
    if (currentAccount == null) {
      throw Exception('[FcmCase] No current account!');
    }
    await _authLocalRepository.updateAccount(
      currentAccount.copyWith(
        fcmTokenUpdatedAt: DateTime.timestamp(),
      ),
    );
    return appId;
  }
}
