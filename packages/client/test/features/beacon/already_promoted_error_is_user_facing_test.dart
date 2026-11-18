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

BeaconSourceAlreadyPromotedException _alreadyPromoted([
  Map<String, dynamic>? details,
]) {
  try {
    throwIfBeaconHierarchyError(1312, details);
  } on BeaconSourceAlreadyPromotedException catch (e) {
    return e;
  }
  fail('code 1312 must be translated to an exception');
}

void main() {
  group('A message that already has a child Request', () {
    test('preserves the visible child id on a localizable conflict', () {
      final error = _alreadyPromoted();

      expect(error.existingChildBeaconId, isNull);
      expect(
        _alreadyPromoted({'beaconId': 'Bexisting001'}).existingChildBeaconId,
        'Bexisting001',
      );
      expect(error, isA<Localizable>());
    });

    test('explains the conflict in English and Russian', () {
      final Object error = _alreadyPromoted();
      expect(error, isA<Localizable>());
      final localizable = error as Localizable;
      final en = localizable.toL10n('en');
      final ru = localizable.toL10n('ru');

      for (final (locale, text) in [('en', en), ('ru', ru)]) {
        final l10n = lookupL10n(Locale(locale));
        expect(text.trim(), isNotEmpty);
        expect(text, isNot(l10n.errorGenericAction));
        expect(text, isNot(contains('Unsupported locale')));
        expect(text, isNot(contains('BeaconSourceAlreadyPromoted')));
        expect(text.trimRight(), isNot(endsWith('...')));
      }
      expect(ru, isNot(en));
      expect(ru, matches(RegExp('[А-Яа-яЁё]')));
    });

    test('is a benign Sentry throwable', () {
      expect(
        isBenignSentryThrowable(_alreadyPromoted()),
        isTrue,
      );
    });
  });

  group('reporting the source that already has a child Request', () {
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
      reportUserFacingError(_alreadyPromoted());
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
