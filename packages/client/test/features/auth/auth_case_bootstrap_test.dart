import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/port/device_push_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

void main() {
  group('AuthCase.bootstrapWebSession', () {
    AuthCase build({
      required FakeAuthLocal local,
      FakeAuthRemote? remote,
    }) =>
        AuthCase(
          local,
          remote ?? FakeAuthRemote(),
          FakeDevicePush(),
          env: const Env(),
          logger: Logger('test'),
        );

    test('session cookie applies when valid', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionUserId: 'U-session');
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(result.sessionUserId, 'U-session');
      expect(result.currentAccountId, 'U-session');
      expect(local.currentAccountId, 'U-session');
    });

    test('rejected session clears cookie and reports rejection', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionRejected: true);
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(remote.clearSessionCookieCalls, 1);
      expect(result.invalidSessionCookieRejected, isTrue);
      expect(result.sessionCookieClearAcknowledged, isTrue);
      expect(result.sessionUserId, isNull);
    });

    test('failed clear leaves sessionCookieClearAcknowledged false', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(
        sessionRejected: true,
        clearAcknowledged: false,
      );
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(result.invalidSessionCookieRejected, isTrue);
      expect(result.sessionCookieClearAcknowledged, isFalse);
    });

    test('rejected session clears ghost session-only local id', () async {
      final local = FakeAuthLocal()
        ..currentAccountId = 'U-ghost'
        ..sessionAccountIds.add('U-ghost')
        ..seedlessAccountIds.add('U-ghost');
      final remote = FakeAuthRemote(sessionRejected: true);
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(result.currentAccountId, isEmpty);
      expect(local.currentAccountId, isNull);
    });

    test('rejected session keeps seed-backed local id', () async {
      final local = FakeAuthLocal()
        ..currentAccountId = 'U-seed'
        ..sessionAccountIds.add('U-seed');
      final remote = FakeAuthRemote(sessionRejected: true);
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(result.currentAccountId, 'U-seed');
      expect(local.currentAccountId, 'U-seed');
    });

    test('network failure does not clear cookie', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionNetworkError: true);
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(remote.clearSessionCookieCalls, 0);
      expect(result.invalidSessionCookieRejected, isFalse);
    });
  });
}

class FakeAuthLocal implements AuthLocalRepositoryPort {
  FakeAuthLocal();

  String? currentAccountId;
  final Map<String, AccountEntity> _accounts = {};
  final Set<String> sessionAccountIds = {};
  final Set<String> seedlessAccountIds = {};

  @override
  Future<AccountEntity?> getAccountById(String id) async => _accounts[id];

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
  }

  @override
  Future<void> upsertAccountWithSeed(
    String id,
    String seed, [
    String? displayName,
  ]) async {
    _accounts[id] = AccountEntity(id: id, displayName: displayName ?? '');
    sessionAccountIds.remove(id);
    seedlessAccountIds.remove(id);
  }

  @override
  Future<void> storeLinkedSeedIfAbsent(String id, String seed) async {}

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
    sessionAccountIds.add(id);
  }

  @override
  Future<bool> isSessionAccount(String id) async => sessionAccountIds.contains(id);

  @override
  Future<void> setCurrentAccountId(String? id) async {
    currentAccountId = id;
  }

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<String> getCurrentAccountId() async => currentAccountId ?? '';
  @override
  Future<String> getSeedByAccountId(String id) async {
    if (seedlessAccountIds.contains(id)) {
      throw const AuthIdNotFoundException();
    }
    return 'seed';
  }
  @override
  Future<List<AccountEntity>> getAccountsAll() async => _accounts.values.toList();
  @override
  Future<AccountEntity?> getCurrentAccount() async => null;
  @override
  Future<void> removeAccount(String id) async {}
  @override
  Future<void> updateAccount(AccountEntity account) async {}
}

class FakeAuthRemote implements AuthRemoteRepositoryPort {
  FakeAuthRemote({
    this.sessionUserId,
    this.sessionRejected = false,
    this.sessionNetworkError = false,
    this.clearAcknowledged = true,
  });

  final String? sessionUserId;
  final bool sessionRejected;
  final bool sessionNetworkError;
  final bool clearAcknowledged;

  int clearSessionCookieCalls = 0;
  int sessionLogoutCalls = 0;

  @override
  Future<void> signOut() async {}

  @override
  Future<String> signIn(String seed) async => '';

  @override
  Future<String> signInWithSession() async {
    if (sessionNetworkError) {
      throw StateError('network');
    }
    if (sessionRejected) {
      throw const SessionAuthRejectedException();
    }
    if (sessionUserId == null) {
      throw StateError('no session');
    }
    return sessionUserId!;
  }

  @override
  Future<void> establishSessionFromBearer() async {}

  @override
  Future<void> sessionLogout() async {
    sessionLogoutCalls++;
  }

  @override
  Future<SessionCookieClearResult> clearSessionCookie() async {
    clearSessionCookieCalls++;
    return clearAcknowledged
        ? SessionCookieClearResult.succeeded
        : SessionCookieClearResult.failed;
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

class FakeDevicePush implements DevicePushPort {
  @override
  Future<void> unregisterCurrentDevice() async {}
}
