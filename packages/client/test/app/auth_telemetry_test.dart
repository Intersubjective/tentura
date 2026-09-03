import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('client auth_telemetry contract', () {
    late String source;

    setUpAll(() {
      source = File('lib/app/sentry/auth_telemetry.dart').readAsStringSync();
    });

    test('emitClientAuthOutcome uses addBreadcrumb, not captureMessage', () {
      expect(source, contains('Sentry.addBreadcrumb'));
      expect(source, isNot(contains('Sentry.captureMessage')));
    });

    test('captureSeedRecoveryFailed still calls captureException', () {
      expect(source, contains('Sentry.captureException'));
    });

    test('Breadcrumb data contains auth_outcome and auth_method', () {
      expect(source, contains("'auth_outcome'"));
      expect(source, contains("'auth_method'"));
    });

    test('Breadcrumb category is auth', () {
      expect(source, contains("category: 'auth'"));
    });
  });
}
