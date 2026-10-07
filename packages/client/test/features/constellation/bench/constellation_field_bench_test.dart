@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';

import '../fixtures/constellation_reference_fixture.dart';
import '../fixtures/synthetic_field.dart';

const _sizes = [100, 300, 600];
const _dragFrames = 30;
const _benchDir = 'build/bench';

Map<String, double> _timeLayout(int size) {
  final field = syntheticConstellationField(size: size);
  const filters = (
    capabilitySlugs: <String>{},
    location: LocationFilter.any,
    timing: TimingFilterAny(),
    includeUnspecified: true,
  );

  final composeWatch = Stopwatch()..start();
  final composed = composeConstellationPresentation(
    viewerId: kRefEgo.id,
    field: field,
    localFilters: filters,
    asOfUtc: field.loadedAt,
    labelBudget: (perPerson: 3, total: 150),
  );
  composeWatch.stop();

  final byAuthor = <String, List<String>>{};
  for (final request in field.requests) {
    byAuthor.putIfAbsent(request.authorId, () => []).add(request.id);
  }
  final layoutWatch = Stopwatch()..start();
  final layout = computeConstellationLayout(
    egoId: kRefEgo.id,
    paths: composed.paths,
    keptPeerIds: composed.keptPeerIds,
    visibleRequestsByAuthor: byAuthor,
    egoOwnRequestIds: {
      for (final r in field.requests)
        if (r.isMine) r.id,
    },
  );
  layoutWatch.stop();
  expect(layout.positions, isNotEmpty);

  return {
    'composeMs': composeWatch.elapsedMicroseconds / 1000,
    'layoutMs': layoutWatch.elapsedMicroseconds / 1000,
  };
}

void main() {
  testWidgets(
    'measures compose, layout and drag frames for each synthetic field size '
    'and writes the baseline JSON',
    (tester) async {
      final results = <String, Object?>{};

      for (final size in _sizes) {
        final timings = _timeLayout(size);

        final cubit = await loadReferenceCubit(
          field: syntheticConstellationField(size: size),
        );
        await pumpConstellationBody(
          tester,
          cubit,
          size: const Size(1200, 800),
        );

        final gesture = await tester.startGesture(const Offset(600, 400));
        final dragWatch = Stopwatch()..start();
        for (var i = 0; i < _dragFrames; i++) {
          await gesture.moveBy(const Offset(4, 2));
          await tester.pump(const Duration(milliseconds: 16));
        }
        dragWatch.stop();
        await gesture.up();
        await tester.pump();

        results['n$size'] = {
          ...timings,
          'dragFrames': _dragFrames,
          'dragFrameMs': dragWatch.elapsedMicroseconds / 1000 / _dragFrames,
        };
        await cubit.close();
      }

      final started = DateTime.now();
      final file = File('$_benchDir/constellation_field_baseline.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'sizes': _sizes,
          'results': results,
        }),
      );

      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final written = decoded['results'] as Map<String, dynamic>;
      for (final size in _sizes) {
        final entry = written['n$size'] as Map<String, dynamic>;
        expect(entry['composeMs'], isA<num>());
        expect(entry['layoutMs'], isA<num>());
        expect(entry['dragFrameMs'], isA<num>());
      }
      expect(
        file.lastModifiedSync().isBefore(
          started.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
