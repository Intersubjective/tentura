import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

SentryEvent _messageEvent(String message) =>
    SentryEvent(message: SentryMessage(message));

SentryEvent _exceptionEvent(String type, String value) => SentryEvent(
  exceptions: [SentryException(type: type, value: value)],
);

Future<SentryEvent?> _runBeforeSend(SentryEvent event) async {
  final options = SentryFlutterOptions();
  configureSentryOptions(options);
  final beforeSend = options.beforeSend;
  expect(beforeSend, isNotNull, reason: 'init must install beforeSend');
  return beforeSend!(event, Hint());
}

void main() {
  late L10n l10n;

  late List<LogRecord> logged;

  /// The message the production `logScreenLoadError` hands to the logger and
  /// to `reportSentryMessage`, captured from the real code path.
  String screenLoad(Object error, {String label = 'MyWork'}) {
    logged.clear();
    logScreenLoadError(
      label: label,
      error: error,
      details: describeScreenLoadError(error: error, l10n: l10n),
    );
    return logged.single.message;
  }

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    logged = [];
    GetIt.I.registerSingleton<Logger>(
      Logger.detached('screen-load-test')..onRecord.listen(logged.add),
    );
  });

  tearDown(() => GetIt.I.reset());

  group('expected offline errors are not Sentry issues', () {
    test('"No Internet connection" text is benign', () {
      expect(isBenignSentryExceptionText('No Internet connection'), isTrue);
    });

    test('connection-uplink screen-load failure is benign', () {
      const error = ConnectionUplinkException();

      expect(isBenignSentryExceptionText(screenLoad(error)), isTrue);
    });

    test(
      'timeout screen-load failure (network kind, other wording) is benign',
      () {
        final error = TimeoutException('load took too long');
        final message = screenLoad(error);

        expect(message, contains('kind=network'));
        expect(message, isNot(contains('No Internet connection')));
        expect(isBenignSentryExceptionText(message), isTrue);
      },
    );

    test('a request timeout is benign like the offline error (#513)', () {
      const error = RequestTimeoutException();

      expect(isBenignSentryThrowable(error), isTrue);
      expect(isBenignSentryExceptionText(screenLoad(error)), isTrue);
    });

    test('screen-load failure for a non-network kind still reports', () {
      const error = RemoteApiException('Internal server error');
      final message = screenLoad(error);

      expect(message, contains('kind=server'));
      expect(isBenignSentryExceptionText(message), isFalse);
    });

    test('message-only event for a timeout screen-load failure is dropped', () {
      final message = screenLoad(TimeoutException('load took too long'));

      expect(isBenignSentryEvent(_messageEvent(message), Hint()), isTrue);
    });

    test('message-only event for a server screen-load failure is kept', () {
      final message = screenLoad(const RemoteApiException('boom'));

      expect(isBenignSentryEvent(_messageEvent(message), Hint()), isFalse);
    });

    test('exception event with offline text is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('Exception', 'No Internet connection'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('exception event typed ConnectionUplinkException is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('ConnectionUplinkException', 'anything at all'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('exception event typed SocketException is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('SocketException', 'Connection refused'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('thrown SocketException is benign', () {
      expect(
        isBenignSentryThrowable(const SocketException('Connection refused')),
        isTrue,
      );
    });

    test('thrown ConnectionUplinkException is benign', () {
      expect(
        isBenignSentryThrowable(const ConnectionUplinkException()),
        isTrue,
      );
    });
  });

  group('expected GraphQL business errors are not Sentry issues', () {
    test('"Description is required" validation text is benign', () {
      expect(isBenignSentryExceptionText('Description is required'), isTrue);
    });

    test('RemoteApiException carrying a validation message is benign', () {
      expect(
        isBenignSentryThrowable(
          const RemoteApiException('Description is required'),
        ),
        isTrue,
      );
    });

    test('"Id not found" text is benign', () {
      expect(isBenignSentryExceptionText('Id not found: [B0123abcd]'), isTrue);
    });

    test('RemoteApiException carrying a not-found message is benign', () {
      expect(
        isBenignSentryThrowable(
          const RemoteApiException('Id not found: [B0123abcd]'),
        ),
        isTrue,
      );
    });

    test('not-found from a non-RemoteApiException throwable is benign', () {
      expect(
        isBenignSentryThrowable(Exception('Id not found: [B0123abcd]')),
        isTrue,
      );
      expect(
        isBenignSentryThrowable(
          const GraphQLException(
            label: 'beaconFetch',
            error: 'Id not found: [B0123abcd]',
          ),
        ),
        isTrue,
      );
    });

    test(
      'validation error from a non-RemoteApiException throwable is benign',
      () {
        expect(
          isBenignSentryThrowable(Exception('Description is required')),
          isTrue,
        );
      },
    );

    test('exception event with not-found text is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('RemoteApiException', 'Id not found: [B0123abcd]'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('not-found exception event of a generic type is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('_Exception', 'Exception: Id not found: [B0123abcd]'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('exception event with validation text is dropped', () {
      expect(
        isBenignSentryEvent(
          _exceptionEvent('RemoteApiException', 'Description is required'),
          Hint(),
        ),
        isTrue,
      );
    });

    test('screen-load failure for a missing id is benign', () {
      final message = screenLoad(
        const RemoteApiException('Id not found: [B0123abcd]'),
        label: 'BeaconView',
      );

      expect(isBenignSentryExceptionText(message), isTrue);
      expect(isBenignSentryEvent(_messageEvent(message), Hint()), isTrue);
    });
  });

  // Rule: an expected class is recognised by what was thrown. A
  // RemoteApiException / GraphQLException / plain Exception carrying the
  // expected text is a business or connectivity error and is dropped; a
  // programming error (StateError, ...) that merely quotes the same text is a
  // real fatal and is kept.
  group('real failures still report to Sentry', () {
    test('unrelated server failures are kept', () {
      expect(
        isBenignSentryThrowable(
          const RemoteApiException('Internal server error'),
        ),
        isFalse,
      );
      expect(
        isBenignSentryEvent(
          _exceptionEvent('StateError', 'Bad state: boom'),
          Hint(),
        ),
        isFalse,
      );
    });

    test(
      'StateError mentioning "Id not found" is kept (programming error, not a not-found response)',
      () {
        final error = StateError(
          'draft merge aborted, Id not found in local cache, state corrupted',
        );

        expect(isBenignSentryThrowable(error), isFalse);
        expect(
          isBenignSentryEvent(
            _exceptionEvent('StateError', error.toString()),
            Hint(),
          ),
          isFalse,
        );
      },
    );

    test(
      'StateError mentioning "Description is required" is kept (programming error, not a validation response)',
      () {
        final error = StateError(
          'draft sync aborted, Description is required was never validated '
          'upstream, state corrupted',
        );

        expect(isBenignSentryThrowable(error), isFalse);
        expect(
          isBenignSentryEvent(
            _exceptionEvent('StateError', error.toString()),
            Hint(),
          ),
          isFalse,
        );
      },
    );

    test(
      'StateError mentioning "No Internet connection" is kept (programming error, not an offline response)',
      () {
        final error = StateError(
          'banner state machine desynced after the No Internet connection '
          'toast, unexpected null',
        );

        expect(isBenignSentryThrowable(error), isFalse);
        expect(
          isBenignSentryEvent(
            _exceptionEvent('StateError', error.toString()),
            Hint(),
          ),
          isFalse,
        );
      },
    );
  });

  group('client Sentry init installs the expected-error filter', () {
    test('beforeSend drops an offline event', () async {
      expect(
        await _runBeforeSend(
          _exceptionEvent(
            'ConnectionUplinkException',
            'No Internet connection',
          ),
        ),
        isNull,
      );
    });

    test('beforeSend drops a timeout screen-load message event', () async {
      final message = screenLoad(TimeoutException('load took too long'));

      expect(await _runBeforeSend(_messageEvent(message)), isNull);
    });

    test('beforeSend drops a validation event', () async {
      expect(
        await _runBeforeSend(
          _exceptionEvent('RemoteApiException', 'Description is required'),
        ),
        isNull,
      );
    });

    test('beforeSend drops a not-found event', () async {
      expect(
        await _runBeforeSend(
          _exceptionEvent('RemoteApiException', 'Id not found: [B0123abcd]'),
        ),
        isNull,
      );
    });

    test('beforeSend keeps a real failure', () async {
      final event = _exceptionEvent('StateError', 'Bad state: boom');

      final kept = await _runBeforeSend(event);

      expect(kept, isNotNull);
      expect(kept!.exceptions?.single.value, 'Bad state: boom');
    });
  });

  group('client Sentry init documents its filter rules', () {
    test('comments name the literal text of each expected-error rule', () {
      // The rules may live next to `configureSentryOptions` or next to the
      // predicate it installs; only comment text is inspected. Paths are
      // relative to packages/client, like the other source-contract tests.
      final comments =
          [
                'lib/app/sentry/sentry_init.dart',
                'lib/app/sentry/sentry_benign_filter.dart',
              ]
              .expand((path) => File(path).readAsLinesSync())
              .where((line) => line.trimLeft().startsWith('//'))
              .join('\n');

      expect(comments, contains('No Internet connection'));
      expect(comments, contains('Description is required'));
      expect(comments, contains('Id not found'));
      expect(comments, contains('kind=network'));
    });
  });
}
