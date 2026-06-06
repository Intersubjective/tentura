import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/session_controller.dart';
import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

final class _FakeSessionRepository implements SessionRepositoryPort {
  final List<String> revokedHashes = [];

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
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async =>
      null;

  @override
  Future<void> revokeByTokenHash(String tokenHash) async {
    revokedHashes.add(tokenHash);
  }

  @override
  Future<void> revokeAllForAccount(String accountId) async {}
}

final class _FakeUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late SessionController controller;
  late _FakeSessionRepository sessionRepo;

  setUp(() {
    sessionRepo = _FakeSessionRepository();
    final env = Env(environment: 'test');
    final authCase = AuthCase(
      _FakeUserRepository(),
      env: env,
      logger: Logger('SessionLogoutTest'),
    );
    final sessionCase = SessionCase(
      sessionRepo,
      authCase,
      env: env,
      logger: Logger('SessionLogoutTest'),
    );
    controller = SessionController(env, sessionCase);
  });

  Future<Response> postLogout({String? cookieHeader}) => controller.logout(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v2/session/logout'),
      headers: cookieHeader == null ? null : {'cookie': cookieHeader},
    ),
  );

  String setCookieHeader(Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) return '';
    if (raw is String) return raw;
    return raw.toString();
  }

  test('logout without cookie still clears session cookie', () async {
    final response = await postLogout();
    expect(response.statusCode, 200);
    final setCookie = setCookieHeader(response);
    expect(setCookie, contains(kCookieSessionName));
    expect(setCookie, contains('Max-Age=0'));
    expect(sessionRepo.revokedHashes, isEmpty);
  });

  test('logout with garbage cookie clears cookie and revokes hash', () async {
    const token = 'garbage-token';
    final response = await postLogout(
      cookieHeader: '$kCookieSessionName=$token',
    );
    expect(response.statusCode, 200);
    final setCookie = setCookieHeader(response);
    expect(setCookie, contains(kCookieSessionName));
    expect(setCookie, contains('Max-Age=0'));
    expect(
      sessionRepo.revokedHashes,
      [SessionCase.hashToken(token)],
    );
  });

  test('logout with valid-looking cookie still emits clearing Set-Cookie', () async {
    const token = 'opaque-valid-token';
    final response = await postLogout(
      cookieHeader: '$kCookieSessionName=$token',
    );
    expect(response.statusCode, 200);
    expect(setCookieHeader(response), contains('Max-Age=0'));
    expect(
      sessionRepo.revokedHashes,
      [SessionCase.hashToken(token)],
    );
  });
}
