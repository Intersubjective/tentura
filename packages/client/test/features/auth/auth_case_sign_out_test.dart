import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/port/device_push_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

void main() {
  test('signOut unregisters push before remote signOut and clearing account',
      () async {
    final order = <String>[];
    final local = FakeAuthLocal(order);
    final remote = FakeAuthRemote(order);
    final push = FakeDevicePush(order);
    final authCase = AuthCase(
      local,
      remote,
      push,
      env: const Env(),
      logger: Logger('test'),
    );

    await authCase.signOut();

    expect(
      order,
      ['unregister', 'signOut', 'clearAccount'],
    );
  });
}

class FakeDevicePush implements DevicePushPort {
  FakeDevicePush(this.order);

  final List<String> order;

  @override
  Future<void> unregisterCurrentDevice() async {
    order.add('unregister');
  }
}

class FakeAuthLocal implements AuthLocalRepositoryPort {
  FakeAuthLocal(this.order);

  final List<String> order;

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getCurrentAccountId() async => 'U1';

  @override
  Future<String> getSeedByAccountId(String id) async => '';

  @override
  Future<List<AccountEntity>> getAccountsAll() async => [];

  @override
  Future<AccountEntity?> getAccountById(String id) async => null;

  @override
  Future<AccountEntity?> getCurrentAccount() async => null;

  @override
  Future<void> addAccount(String id, String seed, [String? displayName]) async {}

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> setCurrentAccountId(String? id) async {
    order.add('clearAccount');
  }
}

class FakeAuthRemote implements AuthRemoteRepositoryPort {
  FakeAuthRemote(this.order);

  final List<String> order;

  @override
  Future<void> signOut() async {
    order.add('signOut');
  }

  @override
  Future<String> signIn(String seed) async => '';

  @override
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async =>
      '';
}
