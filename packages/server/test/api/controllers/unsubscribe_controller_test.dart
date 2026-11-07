import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/unsubscribe_controller.dart';
import 'package:tentura_server/domain/unsubscribe/unsubscribe_token.dart';
import 'package:tentura_server/domain/use_case/unsubscribe_case.dart';
import 'package:tentura_server/env.dart';

const _valid = 'tok-valid';

/// Knows one valid token ([_valid], scope `all`) and records what was applied.
final class _FakeUnsubscribeCase implements UnsubscribeCase {
  final peeked = <String>[];
  final applied = <String>[];

  @override
  UnsubscribePayload? peek(String token) {
    peeked.add(token);
    return token == _valid ? (accountId: 'Uacc', scope: 'all') : null;
  }

  @override
  Future<String?> apply(String token) async {
    applied.add(token);
    return token == _valid ? 'all' : null;
  }
}

void main() {
  late _FakeUnsubscribeCase unsubscribeCase;
  late UnsubscribeController controller;

  setUp(() {
    unsubscribeCase = _FakeUnsubscribeCase();
    controller = UnsubscribeController(
      Env(environment: Environment.test, publicOrigin: 'https://app.test'),
      unsubscribeCase,
    );
  });

  Request request(String method, {String? token, String? formBody}) => Request(
    method,
    Uri(
      scheme: 'http',
      host: 'localhost',
      path: '/email/unsubscribe',
      queryParameters: token == null ? null : {'token': token},
    ),
    body: formBody,
    headers: formBody == null
        ? null
        : {'content-type': 'application/x-www-form-urlencoded'},
  );

  void expectHtmlNoStore(Response r) {
    expect(r.headers['content-type'], startsWith('text/html'));
    expect(r.headers['cache-control'], contains('no-store'));
  }

  group('GET (scanner-safe)', () {
    test('valid token renders the confirm form and applies nothing', () async {
      final r = await controller.getPage(request('GET', token: _valid));

      expect(r.statusCode, 200);
      expectHtmlNoStore(r);
      final html = await r.readAsString();
      expect(html, contains('method="post"'));
      expect(html, contains(_valid));
      expect(unsubscribeCase.applied, isEmpty);
    });

    for (final token in [null, 'tok-bad']) {
      test('400 invalid page for token $token', () async {
        final r = await controller.getPage(request('GET', token: token));
        expect(r.statusCode, 400);
        expectHtmlNoStore(r);
        expect(unsubscribeCase.applied, isEmpty);
      });
    }

    test('handler is the GET page', () async {
      final r = await controller.handler(request('GET', token: _valid));
      expect(r.statusCode, 200);
      expect(unsubscribeCase.applied, isEmpty);
    });
  });

  group('POST', () {
    test('one-click: token in the query is applied', () async {
      final r = await controller.post(request('POST', token: _valid));

      expect(r.statusCode, 200);
      expectHtmlNoStore(r);
      expect(unsubscribeCase.applied, [_valid]);
      expect(
        await r.readAsString(),
        contains('https://app.test/#/notifications'),
      );
    });

    test('confirm form: token in the form body is applied', () async {
      final r = await controller.post(
        request('POST', formBody: 'token=$_valid'),
      );
      expect(r.statusCode, 200);
      expect(unsubscribeCase.applied, [_valid]);
    });

    test('invalid token -> 400 invalid page', () async {
      final r = await controller.post(request('POST', token: 'tok-bad'));
      expect(r.statusCode, 400);
      expectHtmlNoStore(r);
    });

    test('no token anywhere -> 400 (the case sees an empty token)', () async {
      final r = await controller.post(request('POST'));
      expect(r.statusCode, 400);
      expect(unsubscribeCase.applied, ['']);
    });
  });
}
