import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/auth_box.dart';
import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_out.data.gql.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_out.req.gql.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_up.data.gql.dart';
import 'package:tentura/features/auth/data/gql/_g/sign_up.req.gql.dart';
import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart';
import 'package:tentura/features/auth/domain/exception.dart';

void main() {
  group('AuthRemoteRepository realtime binding', () {
    test(
      'signup binds only after server returns authoritative subject',
      () async {
        final client = _FakeAuthRemoteClient();
        final repository = _repository(client);

        final userId = await repository.signUp(
          seed: 'seed',
          displayName: 'Alice',
          invitationCode: 'invite',
        );

        expect(userId, 'account-a');
        expect(client.boundAccountId, 'account-a');
        expect(client.order, ['setAuth', 'request:signup', 'bind:account-a']);
      },
    );

    test('failed signup never binds realtime', () async {
      final client = _FakeAuthRemoteClient()..requestThrows = true;

      await expectLater(
        _repository(client).signUp(
          seed: 'seed',
          displayName: 'Alice',
          invitationCode: 'invite',
        ),
        throwsStateError,
      );

      expect(client.boundAccountId, isNull);
      expect(client.order, ['setAuth', 'request:signup']);
    });

    test(
      'seed signin binds after token and session-cookie convergence',
      () async {
        final client = _FakeAuthRemoteClient();

        final userId = await _repository(client).signIn(
          'seed',
          authAttemptId: 'attempt-1234567890',
        );

        expect(userId, 'account-a');
        expect(client.order, [
          'dropAuth',
          'setAuth',
          'getAuthToken',
          'establishSession',
          'bind:account-a',
        ]);
      },
    );

    test('failed seed session convergence leaves realtime unbound', () async {
      final client = _FakeAuthRemoteClient()
        ..establishSessionError = SessionHttpException(503);

      await expectLater(
        _repository(client).signIn('seed'),
        throwsA(isA<SessionHttpException>()),
      );

      expect(client.boundAccountId, isNull);
      expect(client.order, isNot(contains('bind:account-a')));
    });

    test('cookie signin binds only after access token resolves', () async {
      final client = _FakeAuthRemoteClient();

      final userId = await _repository(client).signInWithSession();

      expect(userId, 'account-a');
      expect(client.order, [
        'dropAuth',
        'setSessionAuth',
        'getAuthToken',
        'bind:account-a',
      ]);
    });

    test('rejected cookie signin remains unbound and maps rejection', () async {
      final client = _FakeAuthRemoteClient()
        ..tokenError = SessionHttpException(401);

      await expectLater(
        _repository(client).signInWithSession(),
        throwsA(isA<SessionAuthRejectedException>()),
      );

      expect(client.boundAccountId, isNull);
      expect(client.order, isNot(contains('bind:account-a')));
    });

    test('signout drops auth and clears the active realtime binding', () async {
      final client = _FakeAuthRemoteClient()
        ..boundAccountId = 'account-a'
        ..validToken = true;

      await _repository(client).signOut();

      expect(client.boundAccountId, isNull);
      expect(client.order, ['request:signout', 'dropAuth']);
    });
  });
}

AuthRemoteRepository _repository(_FakeAuthRemoteClient client) =>
    AuthRemoteRepository(remoteApiService: client, log: Logger('auth-test'));

final class _FakeAuthRemoteClient implements AuthRemoteClient {
  final order = <String>[];
  String? boundAccountId;
  bool requestThrows = false;
  Exception? tokenError;
  Exception? establishSessionError;
  bool validToken = false;
  bool sessionAuth = false;

  Credentials get _credentials => Credentials(
    userId: 'account-a',
    accessToken: 'access-token',
    expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
  );

  @override
  bool get hasValidToken => validToken;

  @override
  bool get isSessionAuth => sessionAuth;

  @override
  Future<void> bindRealtimeAccount(String accountId) async {
    order.add('bind:$accountId');
    boundAccountId = accountId;
  }

  @override
  Future<bool> clearSessionCookie() async => true;

  @override
  Future<void> dropAuth() async {
    order.add('dropAuth');
    boundAccountId = null;
    validToken = false;
    sessionAuth = false;
  }

  @override
  Future<void> establishSessionFromBearer({String? authAttemptId}) async {
    order.add('establishSession');
    final error = establishSessionError;
    if (error != null) throw error;
  }

  @override
  Future<Credentials> getAuthToken() async {
    order.add('getAuthToken');
    final error = tokenError;
    if (error != null) throw error;
    validToken = true;
    return _credentials;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GSignUpReq) {
      order.add('request:signup');
      if (requestThrows) return Stream.error(StateError('signup failed'));
      final data = GSignUpData((b) => b.signUp.subject = 'account-a');
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: data as TData,
        ),
      );
    }
    if (request is GSignOutReq) {
      order.add('request:signout');
      final data = GSignOutData((b) => b.signOut = true);
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: data as TData,
        ),
      );
    }
    return const Stream.empty();
  }

  @override
  Future<void> sessionLogout() async {
    order.add('sessionLogout');
  }

  @override
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    order.add('setAuth');
    return returnAuthRequestToken == null ? null : 'auth-request-token';
  }

  @override
  Future<void> setSessionAuth() async {
    order.add('setSessionAuth');
    sessionAuth = true;
  }
}
