import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/sentry/report_sentry_message.dart';
import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

/// Stands in for the Sentry HTTP transport and keeps every event that would
/// have become a Sentry issue.
class _RecordingTransport implements Transport {
  final events = <SentryEvent>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      final payload = item.originalObject;
      if (payload is SentryEvent) {
        events.add(payload);
      }
    }
    return envelope.header.eventId;
  }

  /// Text a reader would see in the issue title/body.
  List<String> get texts => [
    for (final event in events) ...[
      ?event.message?.formatted,
      for (final ex in event.exceptions ?? const <SentryException>[])
        '${ex.type}: ${ex.value}',
    ],
  ];
}

const _sentinel = 'sentinel failure that must always reach Sentry';

void main() {
  late L10n l10n;
  late _RecordingTransport transport;
  late Logger logger;
  late List<LogRecord> logged;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    transport = _RecordingTransport();
    final options = SentryFlutterOptions();
    configureSentryOptions(options);
    options
      ..dsn = 'https://public@example.invalid/1'
      ..transport = transport
      ..tracesSampleRate = 0
      ..enableLogs = false;
    // `options:` is the only way to hand Sentry.init a SentryFlutterOptions.
    // ignore: invalid_use_of_internal_member
    await Sentry.init((_) {}, options: options);

    logged = [];
    logger = Logger.detached('screen-load-test')..onRecord.listen(logged.add);
    GetIt.I.registerSingleton<Logger>(logger);
  });

  tearDown(() async {
    await Sentry.close();
    await GetIt.I.reset();
  });

  /// Reports a real failure through the same seam and waits until Sentry has
  /// delivered it, so that everything reported before it has been processed.
  Future<void> flush() async {
    reportUserFacingError(StateError(_sentinel));
    for (var i = 0; i < 100; i++) {
      if (transport.texts.any((t) => t.contains(_sentinel))) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('the control failure never reached the Sentry transport');
  }

  List<String> reportedBeforeControl() =>
      transport.texts.where((t) => !t.contains(_sentinel)).toList();

  /// Runs the production `logScreenLoadError` path for [error].
  String logScreenLoad(Object error, {String label = 'MyWork'}) {
    logScreenLoadError(
      label: label,
      error: error,
      details: describeScreenLoadError(error: error, l10n: l10n),
    );
    return logged.single.message;
  }

  group('expected failures reach no Sentry issue through the report seams', () {
    test('offline error shown to the user creates no issue', () async {
      reportUserFacingError(const ConnectionUplinkException());
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test('validation error shown to the user creates no issue', () async {
      reportUserFacingError(
        const RemoteApiException('Description is required'),
      );
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test('not-found error shown to the user creates no issue', () async {
      reportUserFacingError(
        const RemoteApiException('Id not found: [B0123abcd]'),
      );
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test(
      'GraphQL not-found error shown to the user creates no issue',
      () async {
        reportUserFacingError(
          const GraphQLException(
            label: 'beaconFetch',
            error: 'Id not found: [B0123abcd]',
          ),
        );
        await flush();

        expect(reportedBeforeControl(), isEmpty);
      },
    );

    test('offline screen-load failure creates no issue', () async {
      logScreenLoad(TimeoutException('load took too long'));
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test('missing-id screen-load failure creates no issue', () async {
      logScreenLoad(
        const RemoteApiException('Id not found: [B0123abcd]'),
        label: 'BeaconView',
      );
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test('offline message-only diagnostic creates no issue', () async {
      reportSentryMessage('[MyWork] load failed kind=network');
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    });

    test('expected failures are still logged for breadcrumbs', () async {
      final message = logScreenLoad(TimeoutException('load took too long'));
      await flush();

      expect(logged.single.level, Level.WARNING);
      expect(message, contains('load failed'));
    });
  });

  group('real failures still reach Sentry through the report seams', () {
    test('server screen-load failure creates an issue', () async {
      final message = logScreenLoad(const RemoteApiException('boom'));
      await flush();

      expect(message, contains('kind=server'));
      expect(reportedBeforeControl(), [message]);
    });

    test(
      'unexpected server error shown to the user creates an issue',
      () async {
        reportUserFacingError(
          const RemoteApiException('Internal server error'),
        );
        await flush();

        expect(reportedBeforeControl(), hasLength(1));
        expect(
          reportedBeforeControl().single,
          contains('Internal server error'),
        );
      },
    );
  });
}
