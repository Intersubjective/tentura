// Generate only a test harness. Delayed imports keep the current red baseline
// an assertion about absent candidates rather than a missing-import error.
String spatialIndexExecutionProbe({required Uri runner}) =>
    r'''
import 'dart:convert';
import 'dart:io';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';
import '{{runner}}' as benchmark;

const algorithms = ['brute_force', 'sap', 'grid', 'dynamic_aabb'];
int ticks = 0;
Trace? active;
final traces = <String, Trace>{};
final created = <String>{};

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

String key(String algorithm, int n, String mode, int changed) =>
    '$algorithm/$n/$mode/$changed';

class Trace {
  Trace(this.algorithm, this.n, this.k, this.mode, this.changed);
  final String algorithm;
  final int n;
  final int k;
  final String mode;
  final int changed;
  int inserts = 0;
  int removes = 0;
  int queries = 0;
  final operationIds = <String>{};
  final changedIds = <String>{};
  final removedRectangles = <String, LRect>{};
  final clockSamples = <int>[];
  final phaseStart = <String, int>{};
  final phaseEnd = <String, int>{};
  final footprints = <String>{};
  bool capturedPrebuild = false;
}

String footprintKey(num width, num height) =>
    '${(width * 1000000).round()}/${(height * 1000000).round()}';
String footprint(LRect rect) =>
    footprintKey(rect.right - rect.left, rect.bottom - rect.top);

int clock() {
  final value = ticks;
  active?.clockSamples.add(value);
  // Clock-read overhead makes summing phase durations observably different
  // from a timer spanning the entire workload, including maintenance/gaps.
  ticks += 3;
  return value;
}

bool measuredPhase(Trace trace, String phase, num reported) {
  final start = trace.phaseStart[phase];
  if (start == null) return reported == 0;
  final end = trace.phaseEnd[phase]!;
  for (final a in trace.clockSamples) {
    for (final b in trace.clockSamples) {
      if (a > start || b < end || b - a != reported) continue;
      final includesOtherWork = trace.phaseStart.keys.any((other) =>
          other != phase && a < trace.phaseEnd[other]! &&
          b > trace.phaseStart[other]!);
      if (!includesOtherWork) return true;
    }
  }
  return false;
}

// These are forwarding test spies, not candidate implementations. Distinct
// virtual costs per algorithm detect cloned timing rows. Compare all real
// candidate results with the existing oracle without wall-clock thresholds.
class TracedIndex implements SpatialIndex {
  TracedIndex(this.algorithm, this.delegate);
  final String algorithm;
  final SpatialIndex delegate;
  final oracle = BruteForceIndex();
  final rectangles = <String, LRect>{};
  @override
  int get length => delegate.length;

  Trace? charge(String operation) {
    final trace = active;
    if (trace == null) return null; // Untimed prebuild/warm-up.
    check(trace.algorithm == algorithm, 'Wrong implementation in timed case');
    if (trace.mode == 'incremental' && !trace.capturedPrebuild) {
      check(rectangles.length == trace.n, 'Incremental fixture must be prebuilt');
      trace.footprints.addAll(rectangles.values.map(footprint));
      trace.capturedPrebuild = true;
    }
    final a = algorithms.indexOf(algorithm);
    final cost = switch (operation) {
      'insert' => 7 + a * 11,
      'remove' => 9 + a * 13,
      _ => 17 + a * 19,
    };
    final phase = operation == 'query' ? 'query' :
        operation == 'remove' || trace.mode == 'incremental' ?
        'invalidate' : 'build';
    trace.phaseStart.putIfAbsent(phase, () => ticks);
    ticks += cost;
    trace.phaseEnd[phase] = ticks;
    if (operation == 'insert') { trace.inserts++; }
    if (operation == 'remove') { trace.removes++; }
    if (operation == 'query') { trace.queries++; }
    return trace;
  }

  @override
  void insert(String id, LRect rect) {
    final trace = charge('insert');
    trace?.operationIds.add(id);
    trace?.footprints.add(footprint(rect));
    if (trace?.mode == 'incremental') {
      final previous = trace!.removedRectangles[id];
      check(previous != null && previous != rect,
        'Incremental reinsertion must change the removed footprint geometry');
    }
    rectangles[id] = rect;
    delegate.insert(id, rect);
    oracle.insert(id, rect);
    check(delegate.length == oracle.length, 'Candidate insert length differs');
  }

  @override
  bool remove(String id) {
    final trace = charge('remove');
    trace?.changedIds.add(id);
    if (trace?.mode == 'incremental' && rectangles.containsKey(id)) {
      trace!.removedRectangles[id] = rectangles[id]!;
    }
    final actual = delegate.remove(id);
    final expected = oracle.remove(id);
    rectangles.remove(id);
    check(actual == expected && actual, 'Invalidation must remove existing ids');
    check(delegate.length == oracle.length, 'Candidate remove length differs');
    return actual;
  }

  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    charge('query');
    if (active != null) {
      check(delegate.length == active!.n, 'Queries require the full N-item index');
    }
    final actual = delegate.queryOverlaps(rect, exceptId: exceptId);
    final expected = oracle.queryOverlaps(rect, exceptId: exceptId);
    check(actual.length == actual.toSet().length &&
      actual.length == expected.length && actual.toSet().containsAll(expected),
      'Candidate overlap differs from brute-force oracle');
    return actual;
  }
}

Future<void> main() async {
  final real = benchmark.benchmarkIndexFactories;
  check(real.length == algorithms.length, 'Registry must contain four indexes');
  final factories = <String, SpatialIndex Function()>{};
  for (var i = 0; i < algorithms.length; i++) {
    final name = algorithms[i];
    // Capture each algorithm name for its forwarding factory.
    check(real.containsKey(name), 'Missing candidate factory $name');
    factories[name] = () {
      final SpatialIndex index = real[name]!();
      if (name != 'brute_force') {
        check(index is! BruteForceIndex, 'Candidate inherits brute force');
      }
      created.add(name);
      return TracedIndex(name, index);
    };
  }
  final dir = Directory.systemTemp.createTempSync('spatial_clock_');
  try {
    final file = File('${dir.path}/spatial_index.json');
    await benchmark.runSpatialIndexBenchmark(
      indexFactories: factories,
      nowMicros: clock,
      onCaseStart: (String algorithm, int n, int k, String mode, int changed) {
        final id = key(algorithm, n, mode, changed);
        check(!traces.containsKey(id), 'Duplicate timed workload $id');
        active = Trace(algorithm, n, k, mode, changed);
        traces[id] = active!;
      },
      onCaseEnd: () { active = null; },
      reportFile: file,
    );
    check(active == null, 'Timed case must end before report publication');
    check(created.length == 4, 'Runner bypassed distinct candidate factories');
    final rows = (jsonDecode(file.readAsStringSync()) as Map)['cases'] as List;
    check(rows.length == 192 && traces.length == 192, 'Incomplete timed matrix');
    final seen = <String>{};
    for (final row in rows.cast<Map>()) {
      final id = key(row['algorithm'], row['n'], row['mode'], row['changed']);
      check(seen.add(id), 'Duplicate report case $id');
      final trace = traces[id];
      check(trace != null, 'Report contains an unexecuted case $id');
      final t = trace!;
      check([100, 300, 600, 1000].contains(t.n), 'Unexpected fixture size');
      check(t.k >= 60 && t.k <= 72 && row['k'] == t.k, 'Wrong K workload');
      final incremental = t.mode == 'incremental';
      check(!incremental || (t.changed >= 1 && t.changed <= 10), 'Wrong delta');
      final inserts = incremental ? t.changed : t.n;
      final removes = t.mode == 'full' ? 0 : incremental ? t.changed : t.n;
      final queries = t.mode == 'build_invalidate' ? 0 :
          (incremental ? t.changed : t.n) * t.k;
      check(t.inserts == inserts && t.removes == removes && t.queries == queries,
          'Timed operations do not match workload $id');
      check(t.operationIds.length == inserts && t.changedIds.length == removes,
          'Workload must touch distinct required ids $id');
      final reportedFootprints = (row['footprintSizes'] as List).cast<Map>()
          .map((size) => footprintKey(size['width'], size['height'])).toSet();
      check(t.footprints.length > 1 &&
          t.footprints.containsAll(reportedFootprints) &&
          reportedFootprints.containsAll(t.footprints),
          'Reported mixed footprints must be the actual indexed rectangles $id');
      if (incremental) {
        check(t.operationIds.containsAll(t.changedIds),
            'Incremental work must reinsert the same changed ids $id');
      }
      check(measuredPhase(t, 'build', row['buildUs']),
          'Build interval must enclose all actual inserts $id');
      check(measuredPhase(t, 'invalidate', row['invalidateUs']),
          'Invalidation interval must enclose removal and reinsertion $id');
      check(measuredPhase(t, 'query', row['queryUs']),
          'Query interval must enclose actual candidate work $id');
      check(t.clockSamples.length >= 2, 'Workload did not read the injected clock');
      check(t.phaseStart.values.every((start) => t.clockSamples.first <= start) &&
          t.phaseEnd.values.every((end) => t.clockSamples.last >= end),
          'Total timer must surround all maintenance and query operations $id');
      check(row['totalUs'] == t.clockSamples.last - t.clockSamples.first,
          'Total must be the observed end-to-end interval, not arbitrary totals '
          'or a sum omitting inter-phase timing overhead $id');
    }
    stdout.writeln('Spatial index execution probe passed');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
'''
        .replaceAll('{{runner}}', runner.toString());

// A type-only stub used to compile the generated probe independently of the
// intentionally absent benchmark. It never executes benchmark behavior.
const spatialIndexBenchmarkCompileStub = '''
import 'dart:io';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';
final benchmarkIndexFactories = <String, SpatialIndex Function()>{};
Future<void> runSpatialIndexBenchmark({
  required Map<String, SpatialIndex Function()> indexFactories,
  required int Function() nowMicros,
  required void Function(String, int, int, String, int) onCaseStart,
  required void Function() onCaseEnd,
  required File reportFile,
}) => throw UnimplementedError('Compile-only test stub');
''';
