import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/port/device_push_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/data/service/handoff_payload.dart';

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

    test('fresh handoff wins over session cookie account', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionUserId: 'cookie-user');
      final result = await build(local: local, remote: remote).bootstrapWebSession(
        handoffForTest: const HandoffPayload(
          userId: 'handoff-user',
          seed: 'c2VlZA',
        ),
      );

      expect(result.freshHandoffUserId, 'handoff-user');
      expect(result.sessionUserId, 'cookie-user');
      expect(result.currentAccountId, 'handoff-user');
      expect(local.currentAccountId, 'handoff-user');
      expect(remote.sessionLogoutCalls, 1);
    });

    test('session applies when no handoff', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionUserId: 'U-session');
      final result = await build(local: local, remote: remote).bootstrapWebSession();

      expect(result.freshHandoffUserId, isNull);
      expect(result.sessionUserId, 'U-session');
      expect(result.currentAccountId, 'U-session');
      expect(local.currentAccountId, 'U-session');
    });

    test('no sessionLogout when handoff matches session user', () async {
      final local = FakeAuthLocal();
      final remote = FakeAuthRemote(sessionUserId: 'same-user');
      await build(local: local, remote: remote).bootstrapWebSession(
        handoffForTest: const HandoffPayload(
          userId: 'same-user',
          seed: 'c2VlZA',
        ),
      );

      expect(remote.sessionLogoutCalls, 0);
    });
  });
}

class FakeAuthLocal implements AuthLocalRepositoryPort {
  FakeAuthLocal();

  String? currentAccountId;
  final Map<String, AccountEntity> _accounts = {};

  @override
  Future<AccountEntity?> getAccountById(String id) async => _accounts[id];

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
  }

  @override
  Future<void> addSessionAccount(String id, [String? displayName]) async {
    _accounts[id] = AccountEntity(id: id);
  }

  @override
  Future<bool> isSessionAccount(String id) async => false;

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
  Future<String> getSeedByAccountId(String id) async => 'seed';
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
  FakeAuthRemote({this.sessionUserId});

  final String? sessionUserId;
  int sessionLogoutCalls = 0;

  @override
  Future<void> signOut() async {}

  @override
  Future<String> signIn(String seed) async => '';

  @override
  Future<String> signInWithSession() async {
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
