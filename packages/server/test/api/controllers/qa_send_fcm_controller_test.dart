import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/api/controllers/qa_send_fcm_controller.dart';
import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/fcm_token_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/env.dart';

void main() {
  Env env({
    String environment = Environment.test,
    bool qaAuthEnabled = true,
    String qaAuthToken = 'secret',
    String fbProjectId = '',
    String fbClientEmail = '',
    String fbPrivateKey = '',
  }) {
    return Env(
      environment: environment,
      serverUri: Uri.parse('https://test.tentura.local'),
      qaAuthEnabled: qaAuthEnabled,
      qaAuthToken: qaAuthToken,
      fbProjectId: fbProjectId,
      fbClientEmail: fbClientEmail,
      fbPrivateKey: fbPrivateKey,
    );
  }

  Request request({
    Map<String, dynamic>? body,
    String? queryToken = 'secret',
    String? authorization,
  }) {
    final queryParameters = <String, String>{};
    if (queryToken != null) {
      queryParameters['_qa_token'] = queryToken;
    }
    return Request(
      'POST',
      Uri.parse('http://localhost/_qa/send-fcm').replace(
        queryParameters: queryParameters,
      ),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (authorization != null) 'authorization': authorization,
      },
    );
  }

  Future<Map<String, dynamic>> jsonBody(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  test('is disabled when QA auth is not explicitly enabled', () async {
    final controller = QaSendFcmController(
      env(qaAuthEnabled: false),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'userId': 'U1', 'title': 'T', 'body': 'B'}),
    );

    expect(response.statusCode, 404);
  });

  test('is disabled without a QA token', () async {
    final controller = QaSendFcmController(
      env(qaAuthToken: ''),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'userId': 'U1', 'title': 'T', 'body': 'B'}, queryToken: null),
    );

    expect(response.statusCode, 404);
  });

  test('is disabled in production even with valid configuration', () async {
    final controller = QaSendFcmController(
      env(environment: Environment.prod),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'userId': 'U1', 'title': 'T', 'body': 'B'}),
    );

    expect(response.statusCode, 404);
  });

  test('rejects a wrong token without advertising the endpoint', () async {
    final controller = QaSendFcmController(
      env(),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(
        body: {'userId': 'U1', 'title': 'T', 'body': 'B'},
        queryToken: 'wrong',
      ),
    );

    expect(response.statusCode, 404);
  });

  test('accepts bearer token auth', () async {
    final fcmRemote = _CapturingFcmRemote();
    final controller = QaSendFcmController(
      env(),
      fcmRemote,
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(
        body: {'token': 'device-token', 'title': 'T', 'body': 'B'},
        queryToken: null,
        authorization: 'Bearer secret',
      ),
    );

    expect(response.statusCode, 200);
    expect(fcmRemote.lastTokens, {'device-token'});
  });

  test('rejects invalid JSON body', () async {
    final controller = QaSendFcmController(
      env(),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      Request(
        'POST',
        Uri.parse('http://localhost/_qa/send-fcm?_qa_token=secret'),
        body: 'not-json',
        headers: {'content-type': 'application/json'},
      ),
    );

    expect(response.statusCode, 400);
    expect(await response.readAsString(), 'invalid JSON body');
  });

  test('requires title and body', () async {
    final controller = QaSendFcmController(
      env(),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'userId': 'U1', 'title': '  ', 'body': 'B'}),
    );

    expect(response.statusCode, 400);
    expect(await response.readAsString(), 'title and body are required');
  });

  test('requires userId or token', () async {
    final controller = QaSendFcmController(
      env(),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'title': 'T', 'body': 'B'}),
    );

    expect(response.statusCode, 400);
    expect(await response.readAsString(), 'userId or token is required');
  });

  test('returns no_fcm_token_rows when userId has no tokens', () async {
    final controller = QaSendFcmController(
      env(),
      _FakeFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'userId': 'U6fca01549512', 'title': 'T', 'body': 'B'}),
    );

    expect(response.statusCode, 200);
    expect(response.headers[kHeaderCacheControl], kCacheControlNoStore);
    expect(await jsonBody(response), {
      'ok': false,
      'reason': 'no_fcm_token_rows',
      'userId': 'U6fca01549512',
    });
  });

  test('sends to tokens loaded by userId', () async {
    const userId = 'U6fca01549512';
    final fcmRemote = _CapturingFcmRemote();
    final controller = QaSendFcmController(
      env(),
      fcmRemote,
      _FakeFcmTokens(
        byUserId: {
          userId: [
            FcmTokenEntity(
              userId: userId,
              appId: const Uuid().v4obj(),
              platform: 'web',
              token: 'tok-registered',
              createdAt: DateTime.utc(2026),
              lastRefreshedAt: DateTime.utc(2026),
            ),
          ],
        },
      ),
    );

    final response = await controller.sendFcm(
      request(
        body: {
          'userId': userId,
          'title': 'QA test',
          'body': 'Hello',
          'beaconId': 'B220d88332b35',
        },
      ),
    );

    expect(response.statusCode, 200);
    final body = await jsonBody(response);
    expect(body['ok'], true);
    expect(body['devices'], 1);
    expect(body['sent'], 1);
    expect(body['staleTokens'], 0);
    expect(body['mock'], true);
    expect(fcmRemote.lastTokens, {'tok-registered'});
    expect(fcmRemote.lastMessage?.title, 'QA test');
    expect(fcmRemote.lastMessage?.beaconId, 'B220d88332b35');
  });

  test('explicit token overrides userId lookup', () async {
    const userId = 'U6fca01549512';
    final fcmRemote = _CapturingFcmRemote();
    final controller = QaSendFcmController(
      env(),
      fcmRemote,
      _FakeFcmTokens(
        byUserId: {
          userId: [
            FcmTokenEntity(
              userId: userId,
              appId: const Uuid().v4obj(),
              platform: 'web',
              token: 'tok-from-db',
              createdAt: DateTime.utc(2026),
              lastRefreshedAt: DateTime.utc(2026),
            ),
          ],
        },
      ),
    );

    await controller.sendFcm(
      request(
        body: {
          'userId': userId,
          'token': 'explicit-token',
          'title': 'T',
          'body': 'B',
        },
      ),
    );

    expect(fcmRemote.lastTokens, {'explicit-token'});
  });

  test('reports stale tokens from send results', () async {
    final fcmRemote = _CapturingFcmRemote(
      results: [
        FcmTokenNotFoundException(token: 'dead-token-12345678'),
      ],
    );
    final controller = QaSendFcmController(
      env(),
      fcmRemote,
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(
        body: {'token': 'dead-token-12345678', 'title': 'T', 'body': 'B'},
      ),
    );

    final body = await jsonBody(response);
    expect(body['ok'], true);
    expect(body['devices'], 1);
    expect(body['sent'], 0);
    expect(body['staleTokens'], 1);
    expect(body['errors'], [
      {
        'type': 'token_not_found',
        'tokenSuffix': '12345678',
      },
    ]);
  });

  test('mock is false when Firebase server creds are configured', () async {
    final controller = QaSendFcmController(
      env(
        fbProjectId: 'tentura-dev',
        fbClientEmail: 'firebase@tentura-dev.iam.gserviceaccount.com',
        fbPrivateKey: '-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----',
      ),
      _CapturingFcmRemote(),
      _FakeFcmTokens(),
    );

    final response = await controller.sendFcm(
      request(body: {'token': 'tok', 'title': 'T', 'body': 'B'}),
    );

    final body = await jsonBody(response);
    expect(body['mock'], false);
  });
}

class _FakeFcmRemote implements FcmRemoteRepositoryPort {
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async =>
      [];
}

class _CapturingFcmRemote implements FcmRemoteRepositoryPort {
  _CapturingFcmRemote({this.results = const []});

  final List<Exception> results;

  Set<String>? lastTokens;
  FcmNotificationEntity? lastMessage;

  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) async {
    lastTokens = fcmTokens.toSet();
    lastMessage = message;
    return results;
  }
}

class _FakeFcmTokens implements FcmTokenRepositoryPort {
  _FakeFcmTokens({this.byUserId = const {}});

  final Map<String, List<FcmTokenEntity>> byUserId;

  @override
  Future<Iterable<FcmTokenEntity>> getTokensByUserId(String userId) async =>
      byUserId[userId] ?? const [];

  @override
  Future<void> putToken({
    required String userId,
    required String appId,
    required String token,
    required String platform,
  }) async {}

  @override
  Future<void> deleteToken(String token) async {}

  @override
  Future<void> deleteByUserAndApp({
    required String userId,
    required String appId,
  }) async {}
}
