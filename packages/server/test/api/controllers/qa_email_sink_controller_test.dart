import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/qa_email_sink_controller.dart';
import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/api/http/request_log_sanitizer.dart';
import 'package:tentura_server/data/service/email/file_sink_email_sender.dart';
import 'package:tentura_server/env.dart';

void main() {
  late Directory sinkDir;

  setUp(() {
    sinkDir = Directory.systemTemp.createTempSync('tentura-qa-email-sink-');
  });

  tearDown(() {
    if (sinkDir.existsSync()) {
      sinkDir.deleteSync(recursive: true);
    }
  });

  Env env({
    String environment = Environment.test,
    String qaAuthToken = 'secret',
    List<String> qaEmailDomains = const ['test.tentura.local'],
  }) => Env(
    environment: environment,
    serverUri: Uri.parse('https://test.tentura.local'),
    emailDebugSinkDir: sinkDir.path,
    qaAuthToken: qaAuthToken,
    qaEmailDomains: qaEmailDomains,
  );

  Request request({
    String email = 'agent@test.tentura.local',
    String? queryToken = 'secret',
    String? authorization,
  }) {
    final queryParameters = <String, String>{'email': email};
    if (queryToken != null) {
      queryParameters['_qa_token'] = queryToken;
    }
    return Request(
      'GET',
      Uri.parse('http://localhost/_qa/latest-email').replace(
        queryParameters: queryParameters,
      ),
      headers: authorization == null ? null : {'authorization': authorization},
    );
  }

  Future<Map<String, dynamic>> jsonBody(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  void writePayload(
    String email,
    Object payload,
  ) {
    final fileName = FileSinkEmailSender.sanitizeEmailForFileName(email);
    File('${sinkDir.path}/$fileName.json').writeAsStringSync(
      jsonEncode(payload),
    );
  }

  test('is disabled without a QA token', () async {
    final controller = QaEmailSinkController(env(qaAuthToken: ''));

    final response = await controller.latestEmail(
      request(queryToken: null),
    );

    expect(response.statusCode, 404);
  });

  test('is disabled in production even with valid configuration', () async {
    final controller = QaEmailSinkController(
      env(environment: Environment.prod),
    );

    final response = await controller.latestEmail(request());

    expect(response.statusCode, 404);
  });

  test('rejects a wrong token without advertising the endpoint', () async {
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(
      request(queryToken: 'wrong'),
    );

    expect(response.statusCode, 404);
  });

  test('rejects non-allowlisted real email domains', () async {
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(
      request(email: 'real@gmail.com'),
    );

    expect(response.statusCode, 400);
  });

  test('requires exactly one at-sign and non-empty email parts', () async {
    final controller = QaEmailSinkController(env());

    for (final email in [
      'agent@@test.tentura.local',
      '@test.tentura.local',
      'agent@',
    ]) {
      final response = await controller.latestEmail(request(email: email));
      expect(response.statusCode, 400, reason: email);
    }
  });

  test('returns found false for a missing sink file', () async {
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(
      request(email: ' Agent@Test.Tentura.Local '),
    );

    expect(response.statusCode, 200);
    expect(response.headers[kHeaderCacheControl], kCacheControlNoStore);
    expect(await jsonBody(response), {
      'found': false,
      'email': 'agent@test.tentura.local',
    });
  });

  test('returns the latest magic-link fields from the sink file', () async {
    const email = 'agent@test.tentura.local';
    writePayload(email, {
      'kind': 'magicLink',
      'to': email,
      'verifyUrl': 'https://dev.tentura.io/auth/email/verify?t=test-token',
      'sentAt': '2026-06-25T18:00:00.000Z',
      'unrelated': 'not returned',
    });
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(request());

    expect(response.statusCode, 200);
    expect(await jsonBody(response), {
      'found': true,
      'email': email,
      'kind': 'magicLink',
      'verifyUrl': 'https://dev.tentura.io/auth/email/verify?t=test-token',
      'sentAt': '2026-06-25T18:00:00.000Z',
    });
  });

  test('accepts a bearer token', () async {
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(
      request(
        queryToken: null,
        authorization: 'Bearer secret',
      ),
    );

    expect(response.statusCode, 200);
    expect((await jsonBody(response))['found'], false);
  });

  test('returns 500 for invalid sink JSON', () async {
    const email = 'agent@test.tentura.local';
    final fileName = FileSinkEmailSender.sanitizeEmailForFileName(email);
    File('${sinkDir.path}/$fileName.json').writeAsStringSync('not json');
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(request());

    expect(response.statusCode, 500);
    expect(await response.readAsString(), 'invalid debug sink payload');
  });

  test('returns 500 when the sink recipient does not match', () async {
    writePayload('agent@test.tentura.local', {
      'kind': 'magicLink',
      'to': 'other@test.tentura.local',
      'verifyUrl': 'https://example.test/verify',
      'sentAt': '2026-06-25T18:00:00.000Z',
    });
    final controller = QaEmailSinkController(env());

    final response = await controller.latestEmail(request());

    expect(response.statusCode, 500);
    expect(await response.readAsString(), 'debug sink email mismatch');
  });

  group('request log sanitization', () {
    test('redacts QA tokens and preserves other query parameters', () {
      const message =
          'GET /_qa/latest-email?email=agent%40test.tentura.local&_qa_token=long-secret&next=value';

      final sanitized = sanitizeRequestLogMessage(message);

      expect(sanitized, isNot(contains('long-secret')));
      expect(sanitized, contains('_qa_token=<redacted>'));
      expect(sanitized, contains('email=agent%40test.tentura.local'));
      expect(sanitized, contains('&next=value'));
    });

    test('redacts every QA token occurrence', () {
      const message = 'GET /path?_qa_token=first&_qa_token=second';

      final sanitized = sanitizeRequestLogMessage(message);

      expect(sanitized, isNot(contains('first')));
      expect(sanitized, isNot(contains('second')));
      expect(
        RegExp('_qa_token=<redacted>').allMatches(sanitized),
        hasLength(2),
      );
    });
  });
}
