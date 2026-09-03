import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/auth_telemetry.dart';

void main() {
  group('parseOAuthStateQuery', () {
    test('returns csrf only when no dot', () {
      final (csrf, attempt) = parseOAuthStateQuery('stateOnly');
      expect(csrf, 'stateOnly');
      expect(attempt, isNull);
    });

    test('splits csrf and attempt id', () {
      final (csrf, attempt) = parseOAuthStateQuery('csrf123.Gabc1234567890');
      expect(csrf, 'csrf123');
      expect(attempt, 'Gabc1234567890');
    });

    test('drops invalid attempt suffix', () {
      final (csrf, attempt) = parseOAuthStateQuery('csrf123.not!!!valid');
      expect(csrf, 'csrf123');
      expect(attempt, isNull);
    });
  });

  group('isValidAuthAttemptId', () {
    test('accepts opaque ids', () {
      expect(isValidAuthAttemptId('Eabc1234567890'), isTrue);
      expect(isValidAuthAttemptId('Gabc1234567890'), isTrue);
    });

    test('rejects empty and garbage', () {
      expect(isValidAuthAttemptId(''), isFalse);
      expect(isValidAuthAttemptId('short'), isFalse);
      expect(isValidAuthAttemptId('bad!!!'), isFalse);
    });
  });

  group('emitAuthOutcome', () {
    late _FakeHub hub;

    setUp(() {
      hub = _FakeHub();
    });

    test('emits 0 captureMessage calls and 1 breadcrumb with correct data',
        () async {
      await emitAuthOutcomeOnHub(
        hub,
        'email_start_outcome',
        authOutcome: 'sent',
        authAttemptId: 'Eabc1234567890',
        authMethod: 'email',
      );
      expect(hub.capturedMessages, isEmpty);
      expect(hub.breadcrumbs, hasLength(1));
      final b = hub.breadcrumbs.first;
      expect(b.message, 'auth:email_start_outcome');
      expect(b.category, 'auth');
      expect(b.data?['auth_outcome'], 'sent');
      expect(b.data?['auth_method'], 'email');
      expect(b.data?['auth_attempt_id'], 'Eabc1234567890');
    });

    test('omits auth_attempt_id when invalid', () async {
      await emitAuthOutcomeOnHub(
        hub,
        'google_callback_outcome',
        authOutcome: 'success_new',
        authAttemptId: null,
        authMethod: 'google',
      );
      expect(hub.breadcrumbs, hasLength(1));
      expect(hub.breadcrumbs.first.data?.containsKey('auth_attempt_id'), isFalse);
    });
  });
}

class _FakeHub implements Hub {
  final List<String> capturedMessages = [];
  final List<Breadcrumb> breadcrumbs = [];

  @override
  Future<SentryId> captureMessage(
    String? message, {
    SentryLevel? level,
    String? template,
    List<dynamic>? params,
    Hint? hint,
    ScopeCallback? withScope,
  }) async {
    if (message != null) capturedMessages.add(message);
    return SentryId.empty();
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb crumb, {Hint? hint}) async {
    breadcrumbs.add(crumb);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
