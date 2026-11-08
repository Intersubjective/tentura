import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/account_credentials_controller.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/oidc_provider_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_case.dart';
import 'package:tentura_server/domain/use_case/oidc_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';
import '../../support/build_test_invitation_case.dart';
import '../../support/invalid_json_body.dart';
import '../../support/log_capture.dart';

/// Google id-token verification fails with [error] (the controller's
/// exception mapping is what is under test, not the OIDC link itself).
final class _FakeOidcProvider implements OidcProviderPort {
  Exception error = const ContactConflictException();

  @override
  Future<OidcIdentity> verifyGoogleIdToken(
    String idToken, {
    String? expectedNonce,
  }) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// The server's default Ed25519 pair doubles as a device key (see
// credential_case_test.dart): `verifyDeviceAuthRequest` accepts it.
final _publicKey = EdDSAPublicKey.fromPEM(
  Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
);
final _privateKey = EdDSAPrivateKey.fromPEM(
  Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
);

String _authRequestToken() =>
    JWT({'pk': base64UrlEncode(_publicKey.bytes)}).sign(
      _privateKey,
      algorithm: JWTAlgorithm.EdDSA,
      expiresIn: const Duration(minutes: 5),
    );

const _account = 'Uacc';

const _credential = AccountCredentialEntity(
  id: 'Cabc',
  accountId: _account,
  type: CredentialType.ed25519Device,
  identifier: 'pk-1',
);

void main() {
  late MockUserRepositoryPort userRepo;
  late _FakeOidcProvider oidcProvider;
  late AccountCredentialsController controller;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    oidcProvider = _FakeOidcProvider();
    final env = Env(environment: Environment.test);
    final logger = Logger('AccountCredentialsControllerTest');
    final invitationRepo = MockInvitationRepositoryPort();
    final authCase = AuthCase(
      userRepo,
      invitationRepo,
      env: env,
      logger: logger,
    );
    final credentialAuthCase = CredentialAuthCase(
      userRepo,
      MockVerifiedContactRepositoryPort(),
      invitationRepo,
      buildTestInvitationCase(
        invitationRepo: invitationRepo,
        userRepo: userRepo,
        beaconRepo: MockBeaconRepositoryPort(),
        friendshipLookup: MockVoteUserFriendshipLookupPort(),
        contactRepo: MockUserContactRepositoryPort(),
        env: env,
        logger: logger,
      ),
      env: env,
      logger: logger,
    );
    controller = AccountCredentialsController(
      CredentialCase(
        userRepo,
        authCase,
        oidcProvider,
        OidcCase(credentialAuthCase, userRepo, env: env, logger: logger),
        env: env,
        logger: logger,
      ),
    );
  });

  Request request(
    String method, {
    String path = '',
    String? accountId = _account,
    Object? body,
    String? rawBody,
    Map<String, String>? params,
  }) => Request(
    method,
    Uri.parse('http://localhost/api/v2/accounts/me/credentials$path'),
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
    headers: {'content-type': 'application/json'},
    context: {
      if (accountId != null) kContextJwtKey: JwtEntity(sub: accountId),
      'shelf_router/params': ?params,
    },
  );

  Future<Map<String, Object?>> jsonOf(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  LogCapture captureLog() {
    final capture = LogCapture('AccountCredentialsController');
    addTearDown(capture.cancel);
    return capture;
  }

  /// The one SEVERE record an unexpected error leaves before the 500.
  void expectLoggedFailure(LogCapture log, String message, Object error) {
    expect(log.records, hasLength(1));
    final record = log.records.single;
    expect(record.level, Level.SEVERE);
    expect(record.message, message);
    expect(record.error, same(error));
    expect(record.stackTrace, isNotNull);
  }

  Future<void> expectBare500(Response r) async {
    expect(r.statusCode, 500);
    expect(await r.readAsString(), 'Internal Server Error');
  }

  group('auth', () {
    for (final accountId in [null, '']) {
      test('every route answers 401 without a usable jwt sub '
          '(${accountId == null ? 'no jwt' : 'empty sub'})', () async {
        final responses = [
          await controller.list(request('GET', accountId: accountId)),
          await controller.link(
            request('POST', accountId: accountId, body: {'x': 1}),
          ),
          await controller.linkGoogle(
            request('POST', accountId: accountId, body: {'x': 1}),
          ),
          await controller.remove(
            request(
              'DELETE',
              accountId: accountId,
              params: {'credentialId': 'Cabc'},
            ),
          ),
        ];
        expect([for (final r in responses) r.statusCode], everyElement(401));
        verifyZeroInteractions(userRepo);
      });
    }
  });

  group('list', () {
    test('200 with the account credentials', () async {
      when(
        userRepo.listCredentials(accountId: anyNamed('accountId')),
      ).thenAnswer((_) async => [_credential]);

      final r = await controller.list(request('GET'));

      expect(r.statusCode, 200);
      final credentials = (await jsonOf(r))['credentials']! as List;
      expect(credentials.single, containsPair('id', 'Cabc'));
      verify(userRepo.listCredentials(accountId: _account)).called(1);
    });

    test('500 on an unexpected error, logged first', () async {
      final error = StateError('db down');
      when(
        userRepo.listCredentials(accountId: anyNamed('accountId')),
      ).thenThrow(error);
      final log = captureLog();

      final r = await controller.list(request('GET'));

      await expectBare500(r);
      expectLoggedFailure(log, 'credentials.list failed', error);
    });
  });

  group('link', () {
    kInvalidJsonBodies.forEach((name, rawBody) {
      test('400 invalid JSON body on $name', () async {
        final r = await controller.link(request('POST', rawBody: rawBody));
        await expectInvalidJsonBody400(r);
        verifyZeroInteractions(userRepo);
      });
    });

    for (final token in <Object?>[
      null,
      '',
      1,
      true,
      <Object?>[],
      <String, Object?>{},
    ]) {
      test('400 when authRequestToken is $token', () async {
        final r = await controller.link(
          request('POST', body: {'authRequestToken': token}),
        );
        expect(r.statusCode, 400);
        expect(await r.readAsString(), 'authRequestToken is required');
        verifyZeroInteractions(userRepo);
      });
    }

    test('409 when the device key is already linked', () async {
      when(
        userRepo.addCredential(
          accountId: anyNamed('accountId'),
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
          publicData: anyNamed('publicData'),
        ),
      ).thenThrow(const CredentialConflictException());

      final r = await controller.link(
        request('POST', body: {'authRequestToken': _authRequestToken()}),
      );

      expect(r.statusCode, 409);
    });

    test('200 with the linked credential', () async {
      when(
        userRepo.addCredential(
          accountId: anyNamed('accountId'),
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
          publicData: anyNamed('publicData'),
        ),
      ).thenAnswer((_) async => _credential);

      final r = await controller.link(
        request('POST', body: {'authRequestToken': _authRequestToken()}),
      );

      expect(r.statusCode, 200);
      expect(await jsonOf(r), containsPair('id', 'Cabc'));
    });

    test('409 is mapped, not logged', () async {
      when(
        userRepo.addCredential(
          accountId: anyNamed('accountId'),
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
          publicData: anyNamed('publicData'),
        ),
      ).thenThrow(const CredentialConflictException());
      final log = captureLog();

      final r = await controller.link(
        request('POST', body: {'authRequestToken': _authRequestToken()}),
      );

      expect(r.statusCode, 409);
      expect(log.records, isEmpty);
    });

    test('500 on an unexpected error, logged first', () async {
      final error = StateError('db down');
      when(
        userRepo.addCredential(
          accountId: anyNamed('accountId'),
          type: anyNamed('type'),
          identifier: anyNamed('identifier'),
          publicData: anyNamed('publicData'),
        ),
      ).thenThrow(error);
      final log = captureLog();

      final r = await controller.link(
        request('POST', body: {'authRequestToken': _authRequestToken()}),
      );

      await expectBare500(r);
      expectLoggedFailure(log, 'credentials.link failed', error);
    });
  });

  group('linkGoogle', () {
    kInvalidJsonBodies.forEach((name, rawBody) {
      test('400 invalid JSON body on $name', () async {
        final r = await controller.linkGoogle(
          request('POST', rawBody: rawBody),
        );
        await expectInvalidJsonBody400(r);
        verifyZeroInteractions(userRepo);
      });
    });

    for (final token in <Object?>[
      null,
      '',
      1,
      true,
      ['tok'],
      {'idToken': 'tok'},
    ]) {
      test('400 when idToken is $token', () async {
        final r = await controller.linkGoogle(
          request('POST', body: {'idToken': token}),
        );
        expect(r.statusCode, 400);
        expect(await r.readAsString(), 'idToken is required');
      });
    }

    for (final error in const <ExceptionBase>[
      CredentialConflictException(),
      ContactConflictException(),
    ]) {
      test('409 on ${error.runtimeType}', () async {
        oidcProvider.error = error;
        final r = await controller.linkGoogle(
          request('POST', body: {'idToken': 'tok'}),
        );
        expect(r.statusCode, 409);
      });
    }

    test('500 on an unexpected error, logged first', () async {
      final error = Exception('boom');
      oidcProvider.error = error;
      final log = captureLog();

      final r = await controller.linkGoogle(
        request('POST', body: {'idToken': 'tok'}),
      );

      await expectBare500(r);
      expectLoggedFailure(log, 'credentials.linkGoogle failed', error);
    });
  });

  group('remove', () {
    void stubRemove(Object? error) {
      final call = when(
        userRepo.removeCredential(
          accountId: anyNamed('accountId'),
          credentialId: anyNamed('credentialId'),
        ),
      );
      if (error == null) {
        call.thenAnswer((_) async {});
      } else {
        call.thenThrow(error);
      }
    }

    Future<Response> remove([String id = 'Cabc']) => controller.remove(
      request('DELETE', path: '/$id', params: {'credentialId': id}),
    );

    test('400 without a credential id', () async {
      final r = await remove('');
      expect(r.statusCode, 400);
      verifyZeroInteractions(userRepo);
    });

    test('409 when it is the last credential', () async {
      stubRemove(const LastCredentialException());
      expect((await remove()).statusCode, 409);
    });

    test('404 for an unknown credential', () async {
      stubRemove(const IdNotFoundException(id: 'Cabc'));
      expect((await remove()).statusCode, 404);
    });

    test('200 {ok: true} on success', () async {
      stubRemove(null);
      final r = await remove();
      expect(r.statusCode, 200);
      expect(await jsonOf(r), {'ok': true});
      verify(
        userRepo.removeCredential(accountId: _account, credentialId: 'Cabc'),
      ).called(1);
    });

    test('500 on an unexpected error, logged first', () async {
      final error = StateError('db down');
      stubRemove(error);
      final log = captureLog();

      final r = await remove();

      await expectBare500(r);
      expectLoggedFailure(log, 'credentials.remove failed', error);
    });
  });
}
