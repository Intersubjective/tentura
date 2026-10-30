import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import 'my_work_test_support.dart';

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

  List<String> get texts => [
    for (final event in events) ...[
      ?event.message?.formatted,
      for (final ex in event.exceptions ?? const <SentryException>[])
        '${ex.type}: ${ex.value}',
    ],
  ];
}

const _sentinel = 'sentinel failure that must always reach Sentry';

/// The first desk enrich times out; the retry returns hints.
class _TimeoutOnceHints extends FakeRoomHints {
  int calls = 0;

  @override
  Future<Map<String, InboxRoomCardHints>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  ) async {
    calls++;
    if (calls == 1) {
      throw TimeoutException('GraphQL request timed out');
    }
    return super.fetchByBeaconIds(beaconIds);
  }
}

void main() {
  late L10n l10n;
  late _RecordingTransport transport;

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

    GetIt.I.registerSingleton<Logger>(Logger.detached('my-work-load-retry'));
  });

  tearDown(() async {
    await Sentry.close();
    await GetIt.I.reset();
  });

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

  void follow(MyWorkCubit cubit, ScreenLoadReportGate gate) {
    final reports = cubit.stream.listen((state) {
      final error = state.loadError;
      gate.observe(
        label: 'MyWork',
        error: error,
        details: error == null
            ? null
            : describeScreenLoadError(error: error, l10n: l10n),
      );
    });
    addTearDown(() async {
      await reports.cancel();
      await cubit.close();
    });
  }

  test(
    'a My Work load that times out and then succeeds reports nothing',
    () async {
      final hints = _TimeoutOnceHints();
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [
            Beacon.empty.copyWith(id: 'b1'),
          ],
          helpOfferedNonArchived: const [],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(repo: repo, roomHints: hints),
      );
      final gate = ScreenLoadReportGate();
      follow(cubit, gate);

      await cubit.stream
          .firstWhere((s) => s.hasError)
          .timeout(const Duration(seconds: 5));
      expect(hints.calls, 1);

      await cubit.fetch();
      expect(cubit.state.hasError, isFalse);
      expect(
        cubit.state.nonArchivedCards.map((c) => c.beaconId),
        contains('b1'),
      );
      expect(hints.calls, 2);
      await Future<void>.delayed(Duration.zero);
      gate.reportFinal();
      await flush();

      expect(reportedBeforeControl(), isEmpty);
    },
  );

  test('two failed My Work loads are reported once', () async {
    final repo = FakeMyWorkRepository()
      ..fetchInitError = RemoteApiException('Server error (HTTP 503)');
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(repo: repo),
    );
    final gate = ScreenLoadReportGate();
    follow(cubit, gate);

    await cubit.stream
        .firstWhere((s) => s.hasError)
        .timeout(const Duration(seconds: 5));
    expect(repo.fetchInitCallCount, 1);

    repo.fetchInitError = RemoteApiException('Server error (HTTP 504)');
    await cubit.fetch();
    await Future<void>.delayed(Duration.zero);
    expect(repo.fetchInitCallCount, 2);
    expect(cubit.state.hasError, isTrue);
    expect('${cubit.state.loadError}', contains('HTTP 504'));
    gate.reportFinal();
    gate.reportFinal();
    await flush();

    final reported = reportedBeforeControl();
    expect(reported, hasLength(1));
    expect(reported.single, contains('kind=unavailable'));
    expect(reported.single, contains('[MyWork] load failed'));
    expect(reported.single, contains('HTTP 504'));
    expect(reported.single, isNot(contains('HTTP 503')));
  });
}
