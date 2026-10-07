import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'fixtures/constellation_reference_fixture.dart';

// Run the same frame-delivery tests with dart.vm.profile=true as well as the
// default debug constants. The mode assertion prevents a profile check from
// accidentally exercising the detector's debug-only path.
const _requestedMode = String.fromEnvironment(
  'constellation.testMode',
  defaultValue: 'debug',
);

FrameTiming _frame({required int buildUs, required int rasterUs}) {
  const start = 1000000;
  final buildFinish = start + buildUs;
  final rasterFinish = buildFinish + rasterUs;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildFinish,
    rasterStart: buildFinish,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  group('Constellation long-task reporting', () {
    test('detector checks run under the requested build-mode constants', () {
      expect(kReleaseMode, isFalse);
      expect(_requestedMode, anyOf('debug', 'profile'));
      expect(kDebugMode, _requestedMode == 'debug');
      expect(kProfileMode, _requestedMode == 'profile');
    });

    for (final phase in ['build', 'raster']) {
      testWidgets(
        'reports $phase above 50 ms and ignores $phase at or below 50 ms',
        (tester) async {
          final cubit = await loadReferenceCubit();
          addTearDown(cubit.close);
          await pumpConstellationBody(tester, cubit);
          // With dart.vm.profile=true Flutter's own layout-callback assertion
          // fires during any MaterialApp pump (reproduced with a bare
          // LayoutBuilder). Consume it so the final check covers only the
          // synthetic frame delivery below.
          final setupException = tester.takeException();
          if (!kProfileMode) expect(setupException, isNull);

          final messages = <String>[];
          final previousPrint = debugPrint;
          final previousLevel = Logger.root.level;
          debugPrint = (message, {wrapWidth}) {
            if (message != null) messages.add(message);
          };
          Logger.root.level = Level.ALL;
          final subscription = Logger.root.onRecord.listen((record) {
            messages.add('${record.loggerName}: ${record.message}');
          });
          addTearDown(() async {
            debugPrint = previousPrint;
            Logger.root.level = previousLevel;
            await subscription.cancel();
          });

          final callback = tester.binding.platformDispatcher.onReportTimings;
          expect(callback, isNotNull);

          // Total frame duration can exceed 50 ms while neither phase does.
          // The detector must compare each phase, without rounding to ms.
          callback!([
            _frame(buildUs: 30000, rasterUs: 30000),
            _frame(
              buildUs: phase == 'build' ? 49999 : 1000,
              rasterUs: phase == 'raster' ? 49999 : 1000,
            ),
            _frame(
              buildUs: phase == 'build' ? 50000 : 1000,
              rasterUs: phase == 'raster' ? 50000 : 1000,
            ),
          ]);
          await tester.idle();
          expect(messages, isEmpty, reason: '50 ms is an inclusive safe limit');

          // Distinct synthetic durations tie each report to the supplied
          // frame, rather than incidental logging during a render or pump.
          for (final slowUs in [50001, 73007, 110013]) {
            messages.clear();
            callback([
              _frame(
                buildUs: phase == 'build' ? slowUs : 1000,
                rasterUs: phase == 'raster' ? slowUs : 1000,
              ),
            ]);
            await tester.idle();
            // Frame delivery is isolated from rendering. Identify a report by
            // its measured phase and duration, without prescribing log copy.
            final reports = messages
                .where((message) => message.toLowerCase().contains(phase))
                .toList();
            expect(
              reports,
              hasLength(1),
              reason: 'Each synthetic slow frame must produce one report',
            );
            expect(reports.single.toLowerCase(), contains(phase));
            final decimalMs = (slowUs / 1000).toStringAsFixed(3);
            final durationText = Duration(microseconds: slowUs).toString();
            expect(
              reports.single,
              anyOf(
                contains('$slowUs'),
                contains(decimalMs),
                contains(durationText),
                matches(
                  RegExp(
                    '\\b${slowUs ~/ 1000}(?:\\.0+)?\\s*(?:ms|milliseconds)\\b',
                    caseSensitive: false,
                  ),
                ),
                matches(
                  RegExp(
                    '\\b${phase}Ms\\W+${slowUs ~/ 1000}(?![\\d.])',
                    caseSensitive: false,
                  ),
                ),
              ),
              reason:
                  'The report must carry the supplied duration, not an '
                  'unrelated phase message',
            );
            // A following safe frame must not repeat the previous report.
            messages.clear();
            callback([_frame(buildUs: 50000, rasterUs: 50000)]);
            await tester.idle();
            expect(messages, isEmpty);
          }
          // Flutter verifies debugPrint is unset before teardown callbacks run.
          debugPrint = previousPrint;
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
