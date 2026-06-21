import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';

import 'auth_test_helpers.dart';

void main() {
  group('AuthCase.signIn', () {
    test('session-marked account uses signInWithSession not seed', () async {
      final order = <String>[];
      final local = _FakeAuthLocal(order, sessionAccount: true, seed: 'seed');
      final remote = _FakeAuthRemote(order);
      final authCase = buildTestAuthCase(local, remote, order: order);

      await authCase.signIn(userId: 'U1');

      expect(order, ['signInWithSession', 'setCurrent:U1']);
    });

    test('seed-backed account uses seed signIn when not session-marked', () async {
      final order = <String>[];
      final local = _FakeAuthLocal(order, seed: 'my-seed');
      final remote = _FakeAuthRemote(order);
      final authCase = buildTestAuthCase(local, remote, order: order);

      await authCase.signIn(userId: 'U1');

      expect(order, ['signIn:my-seed', 'setCurrent:U1']);
    });
  });
}

class _FakeAuthLocal implements AuthLocalRepositoryPort {
  _FakeAuthLocal(this.order, {this.sessionAccount = false, this.seed = ''});

  final List<String> order;
  final bool sessionAccount;
  final String seed;

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getCurrentAccountId() async => '';

  @override
  Future<String> getSeedByAccountId(String id) async {
    if (seed.isEmpty) throw const AuthIdNotFoundException();
    return seed;
  }

  @override
  Future<List<AccountEntity>> getAccountsAll() async => [];

  @override
  Future<AccountEntity?> getAccountById(String id) async => null;

  @override
  Future<AccountEntity?> getCurrentAccount() async => null;

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
  Future<bool> isSessionAccount(String id) async => sessionAccount;

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> setCurrentAccountId(String? id) async {
    order.add('setCurrent:$id');
  }

  @override
  Future<void> clearAllAuthData() async {}
}

class _FakeAuthRemote implements AuthRemoteRepositoryPort {
  _FakeAuthRemote(this.order) : sessionUserId = 'U1';

  final List<String> order;
  final String sessionUserId;

  @override
  Future<String> signInWithSession() async {
    order.add('signInWithSession');
    return sessionUserId;
  }

  @override
  Future<String> signIn(String seed) async {
    order.add('signIn:$seed');
    return sessionUserId;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> establishSessionFromBearer() async {}

  @override
  Future<void> sessionLogout() async {}

  @override
  Future<SessionCookieClearResult> clearSessionCookie() async =>
      SessionCookieClearResult.succeeded;

  @override
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async =>
      '';
}
