import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('client Sentry observability contract', () {
    test('log bridge records breadcrumbs without creating issues', () {
      final source = File(
        'lib/app/sentry/sentry_log_bridge.dart',
      ).readAsStringSync();

      expect(source, contains('Sentry.addBreadcrumb'));
      expect(source, contains('SentryLevel.error'));
      expect(source, isNot(contains('Sentry.captureException')));
      expect(source, isNot(contains('Sentry.captureMessage')));
    });

    test(
      'remote repository classifies and logs without reporting to Sentry',
      () {
        final source = File(
          'lib/data/repository/remote_repository.dart',
        ).readAsStringSync();

        expect(source, contains('mapRemoteFailure'));
        expect(source, contains('Error.throwWithStackTrace'));
        expect(source, contains('log.warning'));
        expect(source, isNot(contains('log.severe')));
        expect(source, isNot(contains('reportUserFacingError')));
        expect(source, isNot(contains('throwClassifiedRemoteFailure')));
      },
    );

    test('snackbar errors report explicitly and do not severe-log', () {
      final source = File('lib/ui/utils/ui_utils.dart').readAsStringSync();

      expect(source, contains('reportUserFacingError(error'));
      expect(source, contains('warning(fullText'));
      expect(source, isNot(contains('severe(fullText')));
    });

    test('swallowed geo failures are explicitly reported', () {
      final source = File(
        'lib/features/geo/data/repository/geo_repository.dart',
      ).readAsStringSync();

      expect(source, contains('reportUserFacingError(e'));
      expect(source, contains('Failed to read current location'));
      expect(source, isNot(contains('_logger.severe')));
    });
  });
}
