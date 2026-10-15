@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/constellation_reference_fixture.dart';
import '../fixtures/edge_picture_layers.dart';
import '../fixtures/synthetic_field.dart';

const _fieldSize = 300;
const _panFrames = 30;
const _panFrameBudgetMs = 8;

/// Default-run sanity bound: 4x the budget, so load noise cannot fail it.
const _panFrameSanityMs = 32;
const _benchDir = 'build/bench';

void main() {
  testWidgets(
    'a pan frame at 300 people and requests stays under the frame budget '
    'without repainting edges, and the figure is written to JSON',
    (tester) async {
      final cubit = await loadReferenceCubit(
        field: syntheticConstellationField(size: _fieldSize),
      );
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 800));
      await tester.pumpAndSettle();
      expect(cubit.edgeKindByPair, isNotEmpty);

      final camera = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final edgeLayers = edgePictureLayers(tester);
      var edgeRepaints = 0;
      var previous = edgeLayers;

      // Median of per-frame times: a pan frame's cost, not the scheduler's
      // worst moment when the whole directory runs in parallel.
      final frameMs = <double>[];
      for (var i = 0; i < _panFrames; i++) {
        camera.value = camera.value.clone()
          ..setTranslationRaw(
            camera.value.storage[12] + 4,
            camera.value.storage[13] + 2,
            camera.value.storage[14],
          );
        final watch = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 16));
        watch.stop();
        frameMs.add(watch.elapsedMicroseconds / 1000);
        final layers = edgePictureLayers(tester);
        if (!sameEdgeLayers(layers, previous)) edgeRepaints++;
        previous = layers;
      }
      frameMs.sort();
      final panFrameMs = frameMs[frameMs.length ~/ 2];

      final started = DateTime.now();
      final file = File('$_benchDir/constellation_pan_frame.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'size': _fieldSize,
          'panFrames': _panFrames,
          'panFrameMs': panFrameMs,
          'edgeRepaints': edgeRepaints,
        }),
      );
      final written =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(
        file.lastModifiedSync().isBefore(
          started.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );

      expect(
        written['edgeRepaints'],
        0,
        reason: 'Pan frames must reuse the edge layer',
      );
      // Wall-clock frame time depends on machine load (6-16 ms seen for the
      // same code in parallel runs), so the real budget is enforced only by a
      // dedicated serial measurement: TENTURA_ENFORCE_BENCH_BUDGET=1 flutter
      // test -j 1 --tags bench ... Default runs keep the deterministic guard
      // above (no edge repaints) and a loose sanity bound.
      final enforce =
          Platform.environment['TENTURA_ENFORCE_BENCH_BUDGET'] == '1';
      expect(
        written['panFrameMs'] as num,
        lessThan(enforce ? _panFrameBudgetMs : _panFrameSanityMs),
        reason: enforce
            ? 'Pan frame at N = $_fieldSize must stay under the budget'
            : 'Pan frame at N = $_fieldSize is far over budget even allowing '
                  'for machine load; rerun serially with '
                  'TENTURA_ENFORCE_BENCH_BUDGET=1',
      );
    },
    // The bench measures paint and layout of a pan, not the semantics pass
    // testWidgets would otherwise add to every frame (~4 ms at this size).
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
