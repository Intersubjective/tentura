import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/notification/domain/entity/fcm_test_send_result.dart';
import 'package:tentura/features/notification/domain/entity/last_fcm_registration.dart';
import 'package:tentura/features/notification/domain/entity/notification_permissions.dart';
import 'package:tentura/features/notification/domain/port/fcm_local_repository_port.dart';
import 'package:tentura/features/notification/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

void main() {
  late FakeFcmLocal local;
  late FakeFcmRemote remote;
  late FakeSettings settings;
  late FcmCase case_;

  const accountA = 'Uaaa';
  const accountB = 'Ubbb';
  const appId = 'app-1';
  const tokenT = 'token-T';
  const tokenNew = 'token-new';

  setUp(() {
    local = FakeFcmLocal();
    remote = FakeFcmRemote();
    settings = FakeSettings(appId: appId);
    case_ = FcmCase(local, remote, settings);
  });

  group('syncTokenForAccount', () {
    test('skips server when accountId, appId, and token unchanged', () async {
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );
      local.token = tokenT;

      final result = await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
      );

      expect(result, appId);
      expect(remote.registerCalls, 0);
    });

    test('registers when accountId changes but token is the same', () async {
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );
      local.token = tokenT;

      await case_.syncTokenForAccount(
        accountId: accountB,
        platform: 'web',
      );

      expect(remote.registerCalls, 1);
      expect(remote.lastRegister?.token, tokenT);
      expect(remote.lastRegister?.appId, appId);
    });

    test('registers when token changes but accountId and appId are the same',
        () async {
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );
      local.token = tokenNew;

      await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
      );

      expect(remote.registerCalls, 1);
      expect(remote.lastRegister?.token, tokenNew);
      final last = await settings.getLastFcmRegistration();
      expect(last?.token, tokenNew);
    });

    test('forceRegister always calls server', () async {
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );
      local.token = tokenT;

      await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
        forceRegister: true,
      );

      expect(remote.registerCalls, 1);
    });

    test('returns null without server call when token is missing', () async {
      local.token = null;

      final result = await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
      );

      expect(result, isNull);
      expect(remote.registerCalls, 0);
      expect(local.getTokenCalls, 1);
    });

    test('returns null without server call when token is empty', () async {
      local.token = '';

      final result = await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
      );

      expect(result, isNull);
      expect(remote.registerCalls, 0);
    });

    test('creates and persists appId when none exists', () async {
      settings = FakeSettings();
      case_ = FcmCase(local, remote, settings);
      local.token = tokenT;

      final result = await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'android',
      );

      expect(result, isNotNull);
      expect(settings.setAppIdCalls, 1);
      expect(await settings.getAppId(), result);
      expect(remote.registerCalls, 1);
      expect(remote.lastRegister?.appId, result);
    });

    test('uses explicit token without fetching from platform', () async {
      local.token = 'platform-token';

      await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'web',
        token: tokenT,
      );

      expect(local.getTokenCalls, 0);
      expect(remote.lastRegister?.token, tokenT);
    });

    test('persists triple-key registration after successful register', () async {
      local.token = tokenT;

      await case_.syncTokenForAccount(
        accountId: accountA,
        platform: 'ios',
      );

      expect(
        await settings.getLastFcmRegistration(),
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );
    });
  });

  group('unregisterCurrentDevice', () {
    test('clears last registration and deletes on server', () async {
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );

      await case_.unregisterCurrentDevice();

      expect(remote.deleteCalls, 1);
      expect(remote.lastDeleteAppId, appId);
      expect(await settings.getLastFcmRegistration(), isNull);
    });

    test('skips server delete when appId is missing', () async {
      settings = FakeSettings();
      case_ = FcmCase(local, remote, settings);
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );

      await case_.unregisterCurrentDevice();

      expect(remote.deleteCalls, 0);
      expect(await settings.getLastFcmRegistration(), isNotNull);
    });

    test('swallows delete errors and still clears last registration', () async {
      remote.deleteThrows = StateError('network down');
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );

      await expectLater(case_.unregisterCurrentDevice(), completes);

      expect(remote.deleteCalls, 1);
      expect(await settings.getLastFcmRegistration(), isNull);
    });
  });

  group('local passthrough', () {
    test('onTokenRefresh forwards local stream', () async {
      final controller = StreamController<String>();
      local.onTokenRefreshOverride = controller.stream;

      expectLater(case_.onTokenRefresh, emits('refreshed-token'));
      controller.add('refreshed-token');
      await controller.close();
    });

    test('requestPermission forwards to local repository', () async {
      local.permissionResult = const NotificationPermissions(authorized: false);

      final permissions = await case_.requestPermission();

      expect(permissions.authorized, isFalse);
      expect(local.requestPermissionCalls, 1);
    });
  });
  group('getRegistrationInfo', () {
    test('reports serverSynced when last registration matches', () async {
      local.token = tokenT;
      await settings.setLastFcmRegistration(
        const LastFcmRegistration(
          accountId: accountA,
          appId: appId,
          token: tokenT,
        ),
      );

      final info = await case_.getRegistrationInfo(
        accountId: accountA,
        permissionGranted: true,
        platform: 'web',
      );

      expect(info.token, tokenT);
      expect(info.appId, appId);
      expect(info.platform, 'web');
      expect(info.permissionGranted, isTrue);
      expect(info.serverSynced, isTrue);
    });

    test('reports not synced when token missing', () async {
      local.token = null;

      final info = await case_.getRegistrationInfo(
        accountId: accountA,
        permissionGranted: false,
        platform: 'android',
      );

      expect(info.token, isNull);
      expect(info.serverSynced, isFalse);
    });
  });
}

class FakeFcmLocal implements FcmLocalRepositoryPort {
  String? token;
  int getTokenCalls = 0;
  int requestPermissionCalls = 0;
  NotificationPermissions permissionResult =
      const NotificationPermissions(authorized: true);
  Stream<String>? onTokenRefreshOverride;

  @override
  Stream<String> get onTokenRefresh =>
      onTokenRefreshOverride ?? const Stream.empty();

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    return token;
  }

  @override
  Future<NotificationPermissions> requestPermission() async {
    requestPermissionCalls++;
    return permissionResult;
  }
}

class FakeFcmRemote implements FcmRemoteRepositoryPort {
  int registerCalls = 0;
  int deleteCalls = 0;
  Object? deleteThrows;
  ({String appId, String token, String platform})? lastRegister;
  String? lastDeleteAppId;

  @override
  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  }) async {
    registerCalls++;
    lastRegister = (appId: appId, token: token, platform: platform);
  }

  @override
  Future<void> deleteToken({required String appId}) async {
    deleteCalls++;
    lastDeleteAppId = appId;
    if (deleteThrows != null) {
      throw deleteThrows!;
    }
  }

  @override
  Future<FcmTestSendResult> sendTestNotification() async {
    return const FcmTestSendResult(
      ok: true,
      devices: 1,
      sent: 1,
      mock: false,
    );
  }
}

class FakeSettings implements SettingsRepositoryPort {
  FakeSettings({this.appId});

  String? appId;
  int setAppIdCalls = 0;
  LastFcmRegistration? _last;

  @override
  Future<String?> getAppId() async => appId;

  @override
  Future<void> setAppId(String value) async {
    setAppIdCalls++;
    appId = value;
  }

  @override
  Future<LastFcmRegistration?> getLastFcmRegistration() async => _last;

  @override
  Future<void> setLastFcmRegistration(LastFcmRegistration? value) async {
    _last = value;
  }

  @override
  Future<bool?> getIsIntroEnabled() async => null;

  @override
  Future<void> setIsIntroEnabled(bool value) async {}

  @override
  Future<String?> getThemeModeName() async => null;

  @override
  Future<void> setThemeMode(String value) async {}

  @override
  Future<String?> getLocalePreference() async => null;

  @override
  Future<void> setLocalePreference(String value) async {}

  @override
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) async => null;

  @override
  Future<void> setNewStuffInboxLastSeenMs(String accountId, int epochMs) async {}

  @override
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) async => null;

  @override
  Future<void> setNewStuffMyWorkLastSeenMs(String accountId, int epochMs) async {}
}
