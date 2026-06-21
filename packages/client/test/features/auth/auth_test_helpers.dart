import 'package:logging/logging.dart';
import 'package:tentura/domain/port/device_push_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/entity/auth_recovery_outcome.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_platform_cleanup_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/notification/domain/entity/last_fcm_registration.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

class TestDevicePush implements DevicePushPort {
  TestDevicePush([this.order]);

  final List<String>? order;

  @override
  Future<void> unregisterCurrentDevice() async {
    order?.add('unregister');
  }
}

class TestAuthPlatformCleanup implements AuthPlatformCleanupPort {
  TestAuthPlatformCleanup([this.order]);

  final List<String>? order;

  @override
  AuthRecoveryNavigation get signOutNavigationTarget =>
      AuthRecoveryNavigation.none;

  @override
  AuthRecoveryNavigation get resetNavigationTarget =>
      AuthRecoveryNavigation.none;

  @override
  Future<void> clearLocalAuthOnSignOut(AuthLocalRepositoryPort local) async {
    order?.add('clearLocal');
    await local.clearAllAuthData();
  }

  @override
  Future<void> clearAllLocalAuthData(AuthLocalRepositoryPort local) async {
    order?.add('clearAllLocal');
    await local.clearAllAuthData();
  }

  @override
  Future<bool> tryPreferCookieSessionSignIn(
    AuthRemoteRepositoryPort remote,
    AuthLocalRepositoryPort local,
    String userId,
  ) async =>
      false;

  @override
  void applyRecoveryNavigation(AuthRecoveryOutcome outcome) {}

  @override
  void reloadAfterRejectedSession({required bool clearAcknowledged}) {}

  @override
  void noteAuthenticatedBoot() {}

  @override
  void clearStaleSessionBrowserGuard() {
    order?.add('clearStaleGuard');
  }

  @override
  bool get skipSessionCookieBootstrap => false;

  @override
  Future<void> prepareForSignInAgain(AuthLocalRepositoryPort local) async {
    await local.setCurrentAccountId(null);
  }
}

class TestSettingsRepository implements SettingsRepositoryPort {
  TestSettingsRepository([this.order]);

  final List<String>? order;

  @override
  Future<String?> getAppId() async => null;

  @override
  Future<void> setAppId(String value) async {}

  @override
  Future<LastFcmRegistration?> getLastFcmRegistration() async => null;

  @override
  Future<void> setLastFcmRegistration(LastFcmRegistration? value) async {
    if (value == null) {
      order?.add('clearFcmRegistration');
    }
  }

  @override
  Future<bool?> getIsIntroEnabled() async => true;

  @override
  Future<void> setIsIntroEnabled(bool value) async {}

  @override
  Future<String?> getThemeModeName() async => 'system';

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

AuthCase buildTestAuthCase(
  AuthLocalRepositoryPort local,
  AuthRemoteRepositoryPort remote, {
  List<String>? order,
  Logger? logger,
}) =>
    AuthCase(
      local,
      remote,
      TestDevicePush(order),
      TestAuthPlatformCleanup(order),
      TestSettingsRepository(order),
      env: const Env(),
      logger: logger ?? Logger('test'),
    );

class EmptyAuthLocal implements AuthLocalRepositoryPort {
  @override
  Stream<String> currentAccountChanges() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getCurrentAccountId() async => '';

  @override
  Future<String> getSeedByAccountId(String id) async => '';

  @override
  Future<List<AccountEntity>> getAccountsAll() async => [];

  @override
  Future<AccountEntity?> getAccountById(String id) async => null;

  @override
  Future<AccountEntity?> getCurrentAccount() async => null;

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> setCurrentAccountId(String? id) async {}

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {}

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {}

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {}

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {}

  @override
  Future<bool> isSessionAccount(String id) async => false;

  @override
  Future<void> clearAllAuthData() async {}
}

class EmptyAuthRemote implements AuthRemoteRepositoryPort {
  EmptyAuthRemote({this.sessionUserId = 'U1', this.sessionRejected = false});

  final String sessionUserId;
  final bool sessionRejected;
  int clearSessionCookieCalls = 0;

  @override
  Future<void> signOut() async {}

  @override
  Future<String> signIn(String seed) async => '';

  @override
  Future<String> signInWithSession() async {
    if (sessionRejected) {
      throw const SessionAuthRejectedException();
    }
    return sessionUserId;
  }

  @override
  Future<void> establishSessionFromBearer() async {}

  @override
  Future<void> sessionLogout() async {}

  @override
  Future<SessionCookieClearResult> clearSessionCookie() async {
    clearSessionCookieCalls++;
    return SessionCookieClearResult.succeeded;
  }

  @override
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async =>
      '';
}
