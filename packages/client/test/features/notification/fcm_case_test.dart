import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    local = FakeFcmLocal();
    remote = FakeFcmRemote();
    settings = FakeSettings(appId: appId);
    case_ = FcmCase(local, remote, settings);
  });

  test('skips server when accountId, appId, and token unchanged', () async {
    await settings.setLastFcmRegistration(
      LastFcmRegistration(
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
      LastFcmRegistration(
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

  test('forceRegister always calls server', () async {
    await settings.setLastFcmRegistration(
      LastFcmRegistration(
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

  test('unregister clears last registration and deletes on server', () async {
    await settings.setLastFcmRegistration(
      LastFcmRegistration(
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
}

class FakeFcmLocal implements FcmLocalRepositoryPort {
  String? token;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<String?> getToken() async => token;

  @override
  Future<NotificationPermissions> requestPermission() async =>
      const NotificationPermissions(authorized: true);
}

class FakeFcmRemote implements FcmRemoteRepositoryPort {
  int registerCalls = 0;
  int deleteCalls = 0;
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
  }
}

class FakeSettings implements SettingsRepositoryPort {
  FakeSettings({required this.appId});

  final String appId;
  LastFcmRegistration? _last;

  @override
  Future<String?> getAppId() async => appId;

  @override
  Future<void> setAppId(String value) async {}

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
  Future<int?> getNewStuffInboxLastSeenMs(String accountId) async => null;

  @override
  Future<void> setNewStuffInboxLastSeenMs(String accountId, int epochMs) async {}

  @override
  Future<int?> getNewStuffMyWorkLastSeenMs(String accountId) async => null;

  @override
  Future<void> setNewStuffMyWorkLastSeenMs(String accountId, int epochMs) async {}
}
