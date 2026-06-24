import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'auth_test_helpers.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:gql_exec/gql_exec.dart';

void main() {
  group('mapRemoteFailure', () {
    test('HTTP 401 maps to AuthSessionLostException', () {
      expect(
        mapRemoteFailure(const ServerStatusException(401)),
        isA<AuthSessionLostException>(),
      );
    });

    test('resource 403 stays ServerStatusException', () {
      expect(
        mapRemoteFailure(const ServerStatusException(403)),
        isA<ServerStatusException>(),
      );
    });

    test('session access-token 401/403 maps to AuthSessionLostException', () {
      expect(
        mapRemoteFailure(SessionHttpException(401)),
        isA<AuthSessionLostException>(),
      );
      expect(
        mapRemoteFailure(SessionHttpException(403)),
        isA<AuthSessionLostException>(),
      );
    });

    test('transport failures stay ConnectionUplinkException', () {
      expect(
        mapRemoteFailure(Exception('socket closed')),
        isA<ConnectionUplinkException>(),
      );
    });

    test('GraphQL invalid-jwt maps to AuthSessionLostException', () {
      expect(
        mapRemoteFailure(
          const GraphQLError(
            message: 'invalid jwt',
            extensions: {'code': 'invalid-jwt'},
          ),
        ),
        isA<AuthSessionLostException>(),
      );
    });

    test('AuthenticationNoKeyException maps to AuthSessionLostException', () {
      expect(
        mapRemoteFailure(const AuthenticationNoKeyException()),
        isA<AuthSessionLostException>(),
      );
    });
  });

  group('AuthCase.signOut', () {
    test('unregisters push before remote signOut then clears cookie', () async {
      final order = <String>[];
      final authCase = buildTestAuthCase(
        _FakeAuthLocal(order),
        _FakeAuthRemote(order),
        order: order,
      );

      await authCase.signOut();

      expect(
        order,
        [
          'unregister',
          'signOut',
          'clearLocal',
          'clearAllLocal',
          'clearFcmRegistration',
          'clearStaleGuard',
          'clearSessionCookie',
        ],
      );
    });

    test('clears local state when remote signOut fails', () async {
      final order = <String>[];
      final authCase = buildTestAuthCase(
        _FakeAuthLocal(order),
        _FakeAuthRemote(order, signOutThrows: true),
        order: order,
      );

      await authCase.signOut();

      expect(
        order,
        [
          'unregister',
          'signOut',
          'clearLocal',
          'clearAllLocal',
          'clearFcmRegistration',
          'clearStaleGuard',
          'clearSessionCookie',
        ],
      );
    });

    test('push unregister failure does not block cleanup', () async {
      final order = <String>[];
      final authCase = AuthCase(
        _FakeAuthLocal(order),
        _FakeAuthRemote(order),
        _ThrowingDevicePush(order),
        TestAuthPlatformCleanup(order),
        TestSettingsRepository(order),
        env: const Env(),
        logger: Logger('test'),
      );

      await authCase.signOut();

      expect(order, contains('clearLocal'));
      expect(order, contains('clearSessionCookie'));
    });
  });

  group('AuthCase.resetLocalAuthState', () {
    test('wipes all local auth data and clears FCM registration', () async {
      final order = <String>[];
      final authCase = buildTestAuthCase(
        _FakeAuthLocal(order),
        _FakeAuthRemote(order),
        order: order,
      );

      await authCase.resetLocalAuthState();

      expect(order, contains('clearAllLocal'));
      expect(order, contains('clearFcmRegistration'));
      expect(order, contains('clearSessionCookie'));
    });
  });
}

class _ThrowingDevicePush extends TestDevicePush {
  _ThrowingDevicePush(super.order);

  @override
  Future<void> unregisterCurrentDevice() async {
    order?.add('unregister');
    throw StateError('push failed');
  }
}

class _FakeAuthLocal implements AuthLocalRepositoryPort {
  _FakeAuthLocal(this.order);

  final List<String> order;

  @override
  Stream<String> currentAccountChanges() => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getCurrentAccountId() async => 'U1';

  @override
  Future<String> getSeedByAccountId(String id) async => 'seed';

  @override
  Future<List<AccountEntity>> getAccountsAll() async => [
    const AccountEntity(id: 'U1'),
  ];

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
  Future<bool> isSessionAccount(String id) async => false;

  @override
  Future<void> removeAccount(String id) async {}

  @override
  Future<void> updateAccount(AccountEntity account) async {}

  @override
  Future<void> setCurrentAccountId(String? id) async {}

  @override
  Future<void> clearAllAuthData() async {
    order.add('clearAllLocal');
  }
}

class _FakeAuthRemote implements AuthRemoteRepositoryPort {
  _FakeAuthRemote(this.order, {this.signOutThrows = false});

  final List<String> order;
  final bool signOutThrows;

  @override
  Future<void> signOut() async {
    order.add('signOut');
    if (signOutThrows) {
      throw StateError('remote signOut failed');
    }
  }

  @override
  Future<String> signIn(String seed, {String? authAttemptId}) async => '';

  @override
  Future<String> signInWithSession() async => '';

  @override
  Future<void> establishSessionFromBearer({String? authAttemptId}) async {}

  @override
  Future<void> sessionLogout() async {}

  @override
  Future<SessionCookieClearResult> clearSessionCookie() async {
    order.add('clearSessionCookie');
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
