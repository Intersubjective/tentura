import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

const _accountId = 'Uaaaaaaaaaaaa';

final class _FakeUserRepository implements UserRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeInvitationRepository implements InvitationRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeSessionRepository implements SessionRepositoryPort {
  _FakeSessionRepository({this.accountId});

  final String? accountId;

  @override
  Future<AccountSessionEntity?> findActiveByTokenHash(String tokenHash) async {
    final id = accountId;
    if (id == null) return null;
    return AccountSessionEntity(
      id: 'Ss1',
      accountId: id,
      tokenHash: tokenHash,
      expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late AuthCase authCase;
  late AuthMiddleware middleware;

  Future<Response> echoSub(Request request) async {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    return Response.ok(jwt?.sub ?? 'anon');
  }

  Request gqlRequest({String? authorization, String? cookie}) => Request(
    'POST',
    Uri.parse('http://localhost/api/v2/graphql'),
    headers: {
      if (authorization != null) kHeaderAuthorization: authorization,
      if (cookie != null) 'cookie': cookie,
    },
  );

  setUp(() {
    final env = Env(environment: 'test');
    authCase = AuthCase(
      _FakeUserRepository(),
      _FakeInvitationRepository(),
      env: env,
      logger: Logger('AuthMiddlewareTest'),
    );
    middleware = AuthMiddleware(
      authCase,
      SessionCase(
        _FakeSessionRepository(),
        authCase,
        env: env,
        logger: Logger('AuthMiddlewareTest'),
      ),
    );
  });

  group('extractJwtClaims', () {
    test('continues anonymous when Authorization is absent', () async {
      final handler = middleware.extractJwtClaims(echoSub);
      final res = await handler(gqlRequest());
      expect(res.statusCode, 200);
      expect(await res.readAsString(), 'anon');
    });

    test('places verified claims in context', () async {
      final token = authCase.issueAccessToken(_accountId).rawToken;
      final handler = middleware.extractJwtClaims(echoSub);
      final res = await handler(gqlRequest(authorization: 'Bearer $token'));
      expect(res.statusCode, 200);
      expect(await res.readAsString(), _accountId);
    });

    test('returns 401 when Bearer is present but invalid', () async {
      final handler = middleware.extractJwtClaims(echoSub);
      final res = await handler(
        gqlRequest(authorization: 'Bearer not-a-jwt'),
      );
      expect(res.statusCode, 401);
    });

    test('returns 401 when Authorization header is malformed', () async {
      final handler = middleware.extractJwtClaims(echoSub);
      final res = await handler(gqlRequest(authorization: 'Bearer'));
      expect(res.statusCode, 401);
    });
  });

  group('extractJwtOrSessionClaims', () {
    test('falls through to session cookie when Bearer is invalid', () async {
      final env = Env(environment: 'test');
      final withCookie = AuthMiddleware(
        authCase,
        SessionCase(
          _FakeSessionRepository(accountId: _accountId),
          authCase,
          env: env,
          logger: Logger('AuthMiddlewareTest'),
        ),
      );
      final handler = withCookie.extractJwtOrSessionClaims(echoSub);
      final res = await handler(
        gqlRequest(
          authorization: 'Bearer not-a-jwt',
          cookie: '${kCookieSessionName}=sess',
        ),
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), _accountId);
    });
  });
}
