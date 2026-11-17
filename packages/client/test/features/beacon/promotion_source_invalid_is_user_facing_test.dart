// A promotion source the server refuses (code 1311) is an expected business
// rejection: the user reads dedicated copy in their language and nothing is
// reported to Sentry as a crash.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/data/service/remote_api_client/beacon_hierarchy_error_mapper.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _RecordingTransport implements Transport {
  final events = <SentryEvent>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      final payload = item.originalObject;
      if (payload is SentryEvent) events.add(payload);
    }
    return envelope.header.eventId;
  }

  List<String> get texts => [
    for (final event in events) ...[
      ?event.message?.formatted,
      for (final ex in event.exceptions ?? const <SentryException>[])
        '${ex.type}: ${ex.value}',
    ],
  ];
}

const _sentinel = 'sentinel failure that must always reach Sentry';

Object _mappedFrom1311() {
  try {
    throwIfBeaconHierarchyError(1311, null);
  } catch (e) {
    return e;
  }
  fail('code 1311 must be translated to an exception');
}

void main() {
  group('server code 1311 (invalid promotion source)', () {
    test('maps to a localizable promotion-source exception', () {
      final error = _mappedFrom1311();

      expect(error, isA<BeaconPromotionSourceInvalidException>());
      expect(error, isA<Localizable>());
    });

    test('says something dedicated in English and in Russian', () async {
      final error = _mappedFrom1311();
      expect(error, isA<Localizable>());
      final l10n = await L10n.delegate.load(const Locale('en'));
      final localizable = error as Localizable;
      final en = localizable.toL10n('en');
      final ru = localizable.toL10n('ru');

      for (final text in [en, ru]) {
        expect(text.trim(), isNotEmpty);
        expect(text, isNot(l10n.errorGenericAction));
        expect(text, isNot(contains('Unsupported locale')));
        expect(text, isNot(contains('BeaconPromotionSourceInvalid')));
      }
      expect(ru, isNot(en));
      expect(ru, matches(RegExp('[А-Яа-я]')));
    });

    test('is a benign Sentry throwable', () {
      expect(
        isBenignSentryThrowable(const BeaconPromotionSourceInvalidException()),
        isTrue,
      );
    });
  });

  group('reporting the refused promotion source', () {
    late _RecordingTransport transport;

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
    });

    tearDown(Sentry.close);

    test('creates no Sentry issue', () async {
      reportUserFacingError(const BeaconPromotionSourceInvalidException());
      // Control failure proves Sentry is live and has drained the queue.
      reportUserFacingError(StateError(_sentinel));
      for (var i = 0; i < 100; i++) {
        if (transport.texts.any((t) => t.contains(_sentinel))) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(transport.texts.any((t) => t.contains(_sentinel)), isTrue);

      expect(
        transport.texts.where((t) => !t.contains(_sentinel)),
        isEmpty,
      );
    });
  });
}
