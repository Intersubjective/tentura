import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/session_controller.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../domain/use_case/invitation_case_mocks.mocks.dart';
import '../../support/noop_invite_accepted_notification_port.dart';

final class _FakeSessionRepo implements SessionRepositoryPort {
  @override
  Future<({String token, AccountSessionEntity session})> create({
    required String accountId,
    required Duration expiresIn,
    String? credentialId,
  }) async =>
      (
        token: 'session-tok',
        session: AccountSessionEntity(
          id: 'Ss1',
          accountId: accountId,
          tokenHash: 'h',
          expiresAt: DateTime.timestamp().add(expiresIn),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late SessionController controller;

  setUp(() {
    final env = Env(environment: Environment.test);
    final userRepo = MockUserRepositoryPort();
    final invitationRepo = MockInvitationRepositoryPort();
    final sessionCase = SessionCase(
      _FakeSessionRepo(),
      AuthCase(
        userRepo,
        invitationRepo,
        NoopInviteAcceptedNotificationPort(),
        env: env,
        logger: Logger('SessionControllerTest'),
      ),
      env: env,
      logger: Logger('SessionControllerTest'),
    );
    controller = SessionController(env, sessionCase);
  });

  test('fromBearer ignores invalid attempt header for auth', () async {
    const accountId = 'Uabc123456789012345678901234567890';
    final res = await controller.fromBearer(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/session/from-bearer'),
        context: {
          kContextJwtKey: const JwtEntity(sub: accountId),
        },
        headers: {
          kHeaderAuthAttemptId: 'not-valid!!!',
        },
      ),
    );
    expect(res.statusCode, 200);
    expect(res.headers['set-cookie'], contains(kCookieSessionName));
  });

  test('fromBearer accepts valid attempt header metadata', () async {
    const accountId = 'Uabc123456789012345678901234567890';
    final res = await controller.fromBearer(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/session/from-bearer'),
        context: {
          kContextJwtKey: const JwtEntity(sub: accountId),
        },
        headers: {
          kHeaderAuthAttemptId: 'Sabc1234567890',
        },
      ),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(body['ok'], true);
  });
}
