import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_context.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';

void main() {
  group('SentryRequestContext', () {
    late Hub hubA;
    late Hub hubB;
    late String userAId;
    late String userBId;

    setUp(() async {
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@o123.ingest.sentry.io/1'
          ..automatedTestMode = true
          ..tracesSampleRate = 1.0;
      });
      hubA = Sentry.clone();
      hubB = Sentry.clone();
      userAId = 'U${'a' * (kIdLength - 1)}';
      userBId = 'U${'b' * (kIdLength - 1)}';
    });

    tearDown(() async {
      await Sentry.close();
    });

    test('capture scopes user id to the request hub only', () async {
      final transactionA = hubA.startTransaction('GET /a', 'http.server');
      final transactionB = hubB.startTransaction('GET /b', 'http.server');

      final contextA = SentryRequestContext(
        hub: hubA,
        transaction: transactionA,
        sentryRequest: SentryRequest(method: 'GET', url: '/a'),
      );
      final contextB = SentryRequestContext(
        hub: hubB,
        transaction: transactionB,
        sentryRequest: SentryRequest(method: 'GET', url: '/b'),
      );

      await contextA.enrichFromRequest(
        Request('GET', Uri.parse('http://localhost/a')).change(context: {
          kContextJwtKey: JwtEntity(sub: userAId),
        }),
      );
      await contextB.enrichFromRequest(
        Request('GET', Uri.parse('http://localhost/b')).change(context: {
          kContextJwtKey: JwtEntity(sub: userBId),
        }),
      );

      SentryUser? userA;
      SentryUser? userB;
      await hubA.configureScope((scope) async {
        userA = scope.user;
      });
      await hubB.configureScope((scope) async {
        userB = scope.user;
      });

      expect(userA?.id, userAId);
      expect(userB?.id, userBId);

      await transactionA.finish();
      await transactionB.finish();
    });
  });

  group('sanitizeHttpHeaders', () {
    test('filters authorization and cookie headers', () {
      final sanitized = sanitizeHttpHeaders({
        'Authorization': 'Bearer secret',
        'Cookie': 'session=secret',
        'Accept': 'application/json',
      });
      expect(sanitized['Authorization'], '[Filtered]');
      expect(sanitized['Cookie'], '[Filtered]');
      expect(sanitized['Accept'], 'application/json');
    });
  });
}
