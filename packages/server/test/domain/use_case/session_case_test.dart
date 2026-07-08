import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/noop_invite_accepted_notification_port.dart';

final class _FakeSessionRepository implements SessionRepositoryPort {
  String? lastHash;

  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async =>
      (
        token: 'tok',
        session: AccountSessionEntity(
          id: 'Ss1',
          accountId: accountId,
          tokenHash: 'h',
          expiresAt: DateTime.timestamp().add(expiresIn),
        ),
      );

  @override
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async {
    lastHash = tokenHash;
    return AccountSessionEntity(
      id: 'Ss1',
      accountId: 'Uabc',
      tokenHash: tokenHash,
      expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> revokeByTokenHash(String tokenHash) async {}

  @override
  Future<void> revokeAllForAccount(String accountId) async {}

  @override
  Future<void> revokeByCredentialId(String credentialId) async {}
}

final class _FakeUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeSessionRepository sessionRepo;
  late AuthCase authCase;
  late SessionCase case_;

  setUp(() {
    sessionRepo = _FakeSessionRepository();
    authCase = AuthCase(
      _FakeUserRepository(),
      _FakeInvitationRepository(),
      NoopInviteAcceptedNotificationPort(),
      env: Env(environment: 'test'),
      logger: Logger('AuthCaseTest'),
    );
    case_ = SessionCase(
      sessionRepo,
      authCase,
      env: Env(environment: 'test'),
      logger: Logger('SessionCaseTest'),
    );
  });

  test('resolveAccountId returns null for empty token', () async {
    expect(await case_.resolveAccountId(null), isNull);
    expect(await case_.resolveAccountId(''), isNull);
  });

  test('resolveAccountId hashes token and looks up session', () async {
    const token = 'opaque-token';
    expect(await case_.resolveAccountId(token), 'Uabc');
    expect(sessionRepo.lastHash, SessionCase.hashToken(token));
    expect(
      SessionCase.hashToken(token),
      '84d3f23da9b5f51b3269566eff05d3fb23607eeef89567f9cd280b90ca0dbc5c',
    );
  });

  test('accessTokenForAccount delegates to AuthCase.issueAccessToken', () async {
    final map = await case_.accessTokenForAccount('U000000000abc');
    expect(map['access_token'], isNotEmpty);
    expect(map['subject'], 'U000000000abc');
  });
}
