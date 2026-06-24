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
}
