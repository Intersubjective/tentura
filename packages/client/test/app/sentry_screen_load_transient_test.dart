import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

/// The failure `.wait` raises when one branch of a desk load times out.
Future<ParallelWaitError<Object?, Object?>> _parallelTimeout() async {
  try {
    await (
      Future<void>.error(TimeoutException('GraphQL request timed out')),
      Future<void>.value(),
    ).wait;
    // ParallelWaitError is the failure shape under test.
    // ignore: avoid_catching_errors
  } on ParallelWaitError<Object?, Object?> catch (error) {
    return error;
  }
  throw StateError('expected a parallel timeout');
}

Future<ParallelWaitError<Object?, Object?>> _parallelTimeoutAndParse() async {
  try {
    await (
      Future<void>.error(TimeoutException('GraphQL request timed out')),
      Future<void>.error(const FormatException('bad payload')),
    ).wait;
    // ParallelWaitError is the failure shape under test.
    // ignore: avoid_catching_errors
  } on ParallelWaitError<Object?, Object?> catch (error) {
    return error;
  }
  throw StateError('expected a parallel failure');
}

void main() {
  late L10n l10n;
  late List<LogRecord> logged;

  String screenLoad(
    Object error, {
    String label = 'MyWork',
    bool willRetry = false,
  }) {
    logged.clear();
    logScreenLoadError(
      label: label,
      error: error,
      details: describeScreenLoadError(error: error, l10n: l10n),
      willRetry: willRetry,
    );
    return logged.single.message;
  }

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    logged = [];
    GetIt.I.registerSingleton<Logger>(
      Logger.detached('screen-load-transient')..onRecord.listen(logged.add),
    );
  });

  tearDown(() => GetIt.I.reset());

  group('a retried transient screen-load failure is not a Sentry issue', () {
    test('a timeout inside a parallel load is kind=network', () async {
      final error = await _parallelTimeout();
      final message = screenLoad(error, willRetry: true);

      expect(isTransientScreenLoadFailure(error), isTrue);
      expect(message, contains('kind=network'));
      expect(message, contains('retrying=1'));
      expect(isBenignSentryExceptionText(message), isTrue);
    });

    test('a cancelled request that will be retried is kind=cancelled', () {
      for (final error in [
        http.RequestAbortedException(),
        const GraphQLNoDataException(label: 'MyWorkInit'),
      ]) {
        final message = screenLoad(error, willRetry: true);

        expect(isTransientScreenLoadFailure(error), isTrue, reason: '$error');
        expect(message, contains('kind=cancelled'), reason: '$error');
        expect(message, contains('retrying=1'), reason: '$error');
        expect(isBenignSentryExceptionText(message), isTrue, reason: '$error');
      }
    });

    test('a connectivity failure is kind=network', () {
      const error = ConnectionUplinkException();
      final message = screenLoad(error, willRetry: true);

      expect(isTransientScreenLoadFailure(error), isTrue);
      expect(message, contains('kind=network'));
      expect(isBenignSentryExceptionText(message), isTrue);
    });

    test('an unavailable server that will be retried is kind=unavailable', () {
      for (final error in [
        const RemoteApiException('Server error (HTTP 503)'),
        const ServerStatusException(503),
        const ServerStatusException(429),
      ]) {
        final message = screenLoad(error, willRetry: true);

        expect(isTransientScreenLoadFailure(error), isTrue, reason: '$error');
        expect(message, contains('kind=unavailable'), reason: '$error');
        expect(message, contains('retrying=1'), reason: '$error');
        expect(isBenignSentryExceptionText(message), isTrue, reason: '$error');
      }
    });
  });

  group('a load that has failed for good is still reported', () {
    test('an unavailable server that will not be retried is reported', () {
      const error = RemoteApiException('Server error (HTTP 503)');
      final message = screenLoad(error);

      expect(isTransientScreenLoadFailure(error), isTrue);
      expect(message, contains('kind=unavailable'));
      expect(message, isNot(contains('retrying=1')));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('a cancelled request that will not be retried is reported', () {
      final error = http.RequestAbortedException();
      final message = screenLoad(error);

      expect(message, contains('kind=cancelled'));
      expect(message, isNot(contains('retrying=1')));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('a parse error is reported, even when a retry was requested', () {
      const error = FormatException('bad payload');
      final message = screenLoad(error, willRetry: true, label: 'BeaconView');

      expect(isTransientScreenLoadFailure(error), isFalse);
      expect(message, contains('[BeaconView] load failed'));
      expect(message, contains('kind=unknown'));
      expect(message, isNot(contains('retrying=1')));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('a GraphQL error is reported, even when a retry was requested', () {
      const error = RemoteApiException(
        'Cannot query field "x" on type "query_root"',
      );
      final message = screenLoad(error, willRetry: true);

      expect(isTransientScreenLoadFailure(error), isFalse);
      expect(message, contains('[MyWork] load failed'));
      expect(message, contains('kind=server'));
      expect(message, isNot(contains('retrying=1')));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('a GraphQL error that mentions HTTP 500 is not an outage', () {
      const error = RemoteApiException('HTTP 500: column "x" does not exist');
      final message = screenLoad(error, willRetry: true);

      expect(message, contains('kind=server'));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('a mapping error beside a timeout is still reported', () async {
      final error = await _parallelTimeoutAndParse();
      final message = screenLoad(error, willRetry: true);

      expect(isTransientScreenLoadFailure(error), isFalse);
      expect(message, contains('kind=unknown'));
      expect(message, isNot(contains('retrying=1')));
      expect(isBenignSentryExceptionText(message), isFalse);
    });
  });
}
