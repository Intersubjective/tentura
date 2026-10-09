import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

import 'dynamic_aabb_tree_index.dart';
import 'sweep_and_prune_index.dart';
import 'uniform_grid_index.dart';

final benchmarkIndexFactories = <String, SpatialIndex Function()>{
  'brute_force': BruteForceIndex.new,
  'sap': SweepAndPruneIndex.new,
  'grid': UniformGridIndex.new,
  'dynamic_aabb': DynamicAabbTreeIndex.new,
};

const _k = 66;
const _footprints = [(72.0, 72.0), (144.0, 56.0), (196.0, 36.0), (96.0, 112.0)];

List<LRect> _fixture(int n) {
  final random = math.Random(235);
  final columns = math.sqrt(n).ceil();
  final result = <LRect>[];
  for (var i = 0; i < n; i++) {
    final (width, height) = _footprints[i % _footprints.length];
    final left = (i % columns) * 120.0 + random.nextDouble() * 40;
    final top = (i ~/ columns) * 100.0 + random.nextDouble() * 40;
    result.add((
      left: left,
      top: top,
      right: left + width,
      bottom: top + height,
    ));
  }
  return result;
}

LRect _shift(LRect rect, double dx, double dy) => (
  left: rect.left + dx,
  top: rect.top + dy,
  right: rect.right + dx,
  bottom: rect.bottom + dy,
);

List<LRect> _queries(List<LRect> rects) => [
  for (final rect in rects)
    for (var candidate = 0; candidate < _k; candidate++)
      _shift(rect, (candidate % 11 - 5) * 24, (candidate ~/ 11 - 3) * 24),
];

/// Times actual index operations; fixture preparation stays outside each case.
/// Total spans all phases, including clock and inter-phase overhead.
Future<void> runSpatialIndexBenchmark({
  Map<String, SpatialIndex Function()>? indexFactories,
  int Function()? nowMicros,
  void Function(String, int, int, String, int)? onCaseStart,
  void Function()? onCaseEnd,
  File? reportFile,
}) async {
  final factories = indexFactories ?? benchmarkIndexFactories;
  final stopwatch = Stopwatch()..start();
  num clock() =>
      nowMicros?.call() ??
      stopwatch.elapsedTicks * 1000000 / stopwatch.frequency;
  final cases = <Map<String, Object>>[];
  // Warm each implementation before recording JIT timings. The injected
  // execution probe also observes these as untimed preparation.
  for (final factory in factories.values) {
    final warm = factory();
    final rects = _fixture(300);
    for (var i = 0; i < rects.length; i++) {
      warm.insert('$i', rects[i]);
    }
    _queries(rects).forEach(warm.queryOverlaps);
    for (var i = 0; i < rects.length; i++) {
      warm.remove('$i');
    }
  }
  for (final n in [100, 300, 600, 1000]) {
    final rects = _fixture(n);
    for (final entry in factories.entries) {
      for (final (mode, changed) in [
        ('full', 0),
        for (var changed = 1; changed <= 10; changed++)
          ('incremental', changed),
        ('build_invalidate', 0),
      ]) {
        final index = entry.value();
        final updates = [
          for (var i = 0; i < changed; i++) _shift(rects[i], 17, -13),
        ];
        final queries = mode == 'full' ? _queries(rects) : _queries(updates);
        if (mode == 'incremental') {
          for (var i = 0; i < n; i++) {
            index.insert('$i', rects[i]);
          }
        }
        onCaseStart?.call(entry.key, n, _k, mode, changed);
        final start = clock();
        num buildUs = 0;
        num invalidateUs = 0;
        num queryUs = 0;
        var matches = 0;
        if (mode != 'incremental') {
          final phaseStart = clock();
          for (var i = 0; i < n; i++) {
            index.insert('$i', rects[i]);
          }
          buildUs = clock() - phaseStart;
        }
        if (mode != 'full') {
          final phaseStart = clock();
          for (var i = 0; i < (mode == 'incremental' ? changed : n); i++) {
            index.remove('$i');
          }
          for (var i = 0; i < changed; i++) {
            index.insert('$i', updates[i]);
          }
          invalidateUs = clock() - phaseStart;
        }
        if (mode != 'build_invalidate') {
          final phaseStart = clock();
          for (var i = 0; i < queries.length; i++) {
            matches += index
                .queryOverlaps(queries[i], exceptId: '${i ~/ _k}')
                .length;
          }
          queryUs = clock() - phaseStart;
        }
        final totalUs = clock() - start;
        onCaseEnd?.call();
        cases.add({
          'algorithm': entry.key,
          'n': n,
          'k': _k,
          'mode': mode,
          'changed': changed,
          'buildUs': buildUs,
          'invalidateUs': invalidateUs,
          'queryUs': queryUs,
          'totalUs': totalUs,
          'matches': matches,
          'footprintSizes': [
            for (final (width, height) in _footprints)
              {'width': width, 'height': height},
          ],
        });
      }
    }
  }
  final file = reportFile ?? File('build/bench/spatial_index.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'seed': 235,
      'cases': cases,
    })}\n',
  );
}

Future<void> main() async {
  await runSpatialIndexBenchmark();
  stdout.writeln('Wrote build/bench/spatial_index.json');
}
