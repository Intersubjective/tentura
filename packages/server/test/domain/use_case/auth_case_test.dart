import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';

import 'invitation_case_mocks.mocks.dart';
import '../../support/noop_invite_accepted_notification_port.dart';

// Reuse the server's default Ed25519 key pair as the test "device key": the
// pair is self-consistent, so `_verifyAuthRequest` (which verifies the token
// against the public key embedded in its payload) accepts it.
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

void main() {
  late MockUserRepositoryPort userRepo;
  late MockInvitationRepositoryPort invitationRepo;
  late AuthCase case_;

  setUp(() {
    userRepo = MockUserRepositoryPort();
    invitationRepo = MockInvitationRepositoryPort();
    when(
      invitationRepo.getById(invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async => null);
    case_ = AuthCase(
      userRepo,
      invitationRepo,
      NoopInviteAcceptedNotificationPort(),
      env: Env(environment: Environment.test),
      logger: Logger('AuthCaseTest'),
    );
  });

  test('signIn resolves the account via the ed25519_device credential', () async {
    when(
      userRepo.getByCredential(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => const UserEntity(id: 'Uacc', displayName: 'Bob'));
    when(
      userRepo.findCredentialId(
        type: anyNamed('type'),
        identifier: anyNamed('identifier'),
      ),
    ).thenAnswer((_) async => 'Cdevice');

    final jwt = await case_.signIn(authRequestToken: _authRequestToken());

    expect(jwt.sub, 'Uacc');
    expect(jwt.credentialId, 'Cdevice');
    final payload = JWT.decode(jwt.rawToken).payload as Map<String, dynamic>;
    expect(payload['cid'], 'Cdevice');
    verify(
      userRepo.getByCredential(type: 'ed25519_device', identifier: _pkB64),
    ).called(1);
  });

  test('signUpWithInvite creates the invited account and issues a session', () async {
    when(
      userRepo.createInvited(
        invitationId: anyNamed('invitationId'),
        publicKey: anyNamed('publicKey'),
        displayName: anyNamed('displayName'),
        handle: anyNamed('handle'),
      ),
    ).thenAnswer(
      (_) async => const UserEntity(id: 'Unew', displayName: 'Carol'),
    );

    final jwt = await case_.signUpWithInvite(
      authRequestToken: _authRequestToken(),
      invitationId: 'Iabc',
      displayName: 'Carol',
    );

    expect(jwt.sub, 'Unew');
    verify(
      userRepo.createInvited(
        invitationId: 'Iabc',
        publicKey: _pkB64,
        displayName: 'Carol',
      ),
    ).called(1);
  });
}
