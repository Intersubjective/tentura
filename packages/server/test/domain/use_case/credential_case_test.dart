import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/credential_case.dart';

import 'invitation_case_mocks.mocks.dart';

// Reuse the server's default Ed25519 key pair as a test "device key" (the pair
// is self-consistent, so `verifyDeviceAuthRequest` accepts the auth-request).
final _publicKey = EdDSAPublicKey.fromPEM(
  Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
);
final _privateKey = EdDSAPrivateKey.fromPEM(
  Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
);
final _pkB64 = base64UrlEncode(_publicKey.bytes);

String _authRequestToken() => JWT({'pk': _pkB64}).sign(
  _privateKey,
  algorithm: JWTAlgorithm.EdDSA,
  expiresIn: const Duration(minutes: 5),
);

AccountCredentialEntity _credential({
  String id = 'Cabc',
  String identifier = 'pk-1',
}) => AccountCredentialEntity(
  id: id,
  accountId: 'Uacc',
  type: CredentialType.ed25519Device,
  identifier: identifier,
);

void main() {
  // NOTE: the conflict / last-credential guards themselves live in
  // `UserRepository` (unique index + `FOR UPDATE` count) and need a real
  // Postgres to exercise. These unit tests cover `CredentialCase` wiring and
  // that repository exceptions propagate unchanged.
  late MockUserRepositoryPort userRepo;
  late CredentialCase case_;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    final env = Env(environment: Environment.test);
    case_ = CredentialCase(
      userRepo,
      AuthCase(userRepo, env: env, logger: Logger('AuthCaseTest')),
      env: env,
      logger: Logger('CredentialCaseTest'),
    );
  });

  test('list returns the account credentials', () async {
    when(
      userRepo.listCredentials(accountId: anyNamed('accountId')),
    ).thenAnswer((_) async => [_credential()]);

    final result = await case_.list(accountId: 'Uacc');

    expect(result, hasLength(1));
    expect(result.single.id, 'Cabc');
    verify(userRepo.listCredentials(accountId: 'Uacc')).called(1);
  });

  test('linkDevice verifies the auth-request and links the device key', () async {
    when(
      userRepo.addCredential(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
      ),
    ).thenAnswer((_) async => _credential(identifier: _pkB64));

    final result = await case_.linkDevice(
      accountId: 'Uacc',
      authRequestToken: _authRequestToken(),
    );

    expect(result.identifier, _pkB64);
    verify(
      userRepo.addCredential(
        accountId: 'Uacc',
        type: CredentialType.ed25519Device,
        identifier: _pkB64,
      ),
    ).called(1);
  });

  test('linkDevice propagates a conflict from the repository', () async {
    when(
      userRepo.addCredential(
        accountId: anyNamed('accountId'),
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
        publicData: anyNamed('publicData'),
      ),
    ).thenThrow(const CredentialConflictException());

    expect(
      () => case_.linkDevice(
        accountId: 'Uacc',
        authRequestToken: _authRequestToken(),
      ),
      throwsA(isA<CredentialConflictException>()),
    );
  });

  test('remove delegates to the repository', () async {
    when(
      userRepo.removeCredential(
        accountId: anyNamed('accountId'),
        credentialId: anyNamed('credentialId'),
      ),
    ).thenAnswer((_) async {});

    await case_.remove(accountId: 'Uacc', credentialId: 'Cabc');

    verify(
      userRepo.removeCredential(accountId: 'Uacc', credentialId: 'Cabc'),
    ).called(1);
  });

  test('remove propagates the last-credential guard from the repository', () async {
    when(
      userRepo.removeCredential(
        accountId: anyNamed('accountId'),
        credentialId: anyNamed('credentialId'),
      ),
    ).thenThrow(const LastCredentialException());

    expect(
      () => case_.remove(accountId: 'Uacc', credentialId: 'Cabc'),
      throwsA(isA<LastCredentialException>()),
    );
  });
}
