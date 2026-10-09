// Pure domain probes use the workspace's transitive test dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'existing_layout_fixture_replay.dart';

Directory _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (!File('${directory.path}/compose.prod.yaml').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Tentura repository root not found');
    }
    directory = parent;
  }
  return directory;
}

/// Delayed imports follow the spatial-index execution probe convention:
/// the red baseline is an assertion about the absent production API rather
/// than a missing import that prevents all test descriptions from loading.
Future<Map<String, dynamic>> runResumableLayoutProbe(String mode) async {
  final root = _repositoryRoot();
  final engine = File(
    '${root.path}/packages/client/lib/features/constellation/domain/layout/'
    'constellation_layout_engine.dart',
  );
  expect(
    engine.existsSync(),
    isTrue,
    reason:
        'Resumable layout requires ConstellationLayoutEngine.start(previous, '
        'next) and LayoutJob.step(units); only synchronous placement exists.',
  );
  final temporary = Directory.systemTemp.createTempSync('resumable-layout-');
  try {
    final source = File('${temporary.path}/probe.dart');
    final snapshot = File('${temporary.path}/probe.dill');
    final fixtures = File(
      '${root.path}/packages/client/test/features/constellation/fixtures/'
      'resumable_layout_inputs.dart',
    );
    final replay = writeExistingLayoutFixtureReplay(root, temporary);
    source.writeAsStringSync(
      _executionProbe
          .replaceAll('{{fixtures}}', fixtures.uri.toString())
          .replaceAll('{{existingFixtures}}', replay.library.toString()),
    );
    return await _runDartProbe(root, source, snapshot, mode);
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

/// Validate fixture replay even while the new engine API is absent. This runs
/// only as preparation inside the new full-plan oracle test, not a new suite.
Future<Map<String, dynamic>> runExistingLayoutFixtureCoverageProbe() async {
  final root = _repositoryRoot();
  final temporary = Directory.systemTemp.createTempSync('layout-fixtures-');
  try {
    final replay = writeExistingLayoutFixtureReplay(root, temporary);
    final source = File('${temporary.path}/coverage.dart')
      ..writeAsStringSync('''
import 'dart:convert';
import '${replay.library}';
void main(List<String> args) {
  final sites = <String>{};
  final counts = <String, int>{};
  replayExistingLayoutFixtures((fixture, site, input, legacy) {
    sites.add(site);
    final file = site.split(':').first;
    counts.update(file, (count) => count + 1, ifAbsent: () => 1);
  });
  print(jsonEncode({'sites': sites.toList(), 'fixtureCounts': counts}));
}
''');
    final result = await _runDartProbe(
      root,
      source,
      File('${temporary.path}/coverage.dill'),
      'coverage',
    );
    expect((result['sites'] as List<dynamic>).toSet(), replay.sites);
    expect(
      (result['fixtureCounts'] as Map<String, dynamic>).keys.toSet(),
      existingLayoutFixtureFiles,
    );
    return result;
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<Map<String, dynamic>> _runDartProbe(
  Directory root,
  File source,
  File snapshot,
  String mode,
) async {
  // Platform.resolvedExecutable is flutter_tester under flutter test.
  final executableName = Platform.resolvedExecutable
      .split(Platform.pathSeparator)
      .last;
  final executable = executableName == 'dart' || executableName == 'dart.exe'
      ? Platform.resolvedExecutable
      : 'dart';
  final compiled = await Process.run(executable, [
    '--packages=${root.path}/.dart_tool/package_config.json',
    '--snapshot-kind=kernel',
    '--snapshot=${snapshot.path}',
    source.path,
  ]);
  expect(
    compiled.exitCode,
    0,
    reason: '${compiled.stdout}\n${compiled.stderr}',
  );
  final executed = await Process.run(executable, [snapshot.path, mode]);
  expect(
    executed.exitCode,
    0,
    reason: '${executed.stdout}\n${executed.stderr}',
  );
  return jsonDecode(executed.stdout as String) as Map<String, dynamic>;
}

// This is exclusively a caller of the proposed production API. It contains
// no replacement engine, job implementation, placement or timing simulation.
// Input remains the existing ConstellationPlacedLayoutInput record. Results
// expose positions and ring, as the legacy ConstellationLayout does.
const _executionProbe = r'''
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_layout_engine.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';
import '{{fixtures}}';
import '{{existingFixtures}}';

const maxSteps = 10000000;

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Map<String, Object> geometry(dynamic result) => {
  'positions': {
    for (final String id in result.positions.keys)
      id: {'x': result.positions[id].x, 'y': result.positions[id].y},
  },
  'ring': result.ring,
};

dynamic finish(dynamic job, {int units = 1}) {
  for (var step = 0; step < maxSteps; step++) {
    if (job.step(units) as bool) return job.result;
  }
  throw StateError('Layout job did not finish after $maxSteps calls');
}

String unfinishedResultAccess(dynamic job) {
  try {
    job.result;
    return 'readable';
  } catch (error) {
    return error.runtimeType.toString();
  }
}

Map<String, Object> stepping() {
  final engine = ConstellationLayoutEngine(newIndex: BruteForceIndex.new);
  final cases = <String, Object>{};
  for (final entry in legacyLayoutInputs().entries) {
    final input = entry.value;
    final previous = finish(engine.start(null, input), units: maxSteps);
    final next = withLayoutChanges(
      input,
      anchors: {
        for (final anchor in input.anchorByNodeId.entries)
          anchor.key: layoutAnchor(-anchor.value.xUnits, -anchor.value.yUnits),
      },
      sizes: {
        ...input.nodeSizes,
        for (final id in input.automaticKeptPeerIds.take(1))
          id: (width: 80.0, height: 80.0),
      },
    );
    for (final incremental in [false, true]) {
      final before = incremental ? previous : null;
      final target = incremental ? next : input;
      final oneUnit = finish(engine.start(before, target));
      final oneShot = finish(engine.start(before, target), units: maxSteps);
      final uneven = engine.start(before, target);
      const batches = [1, 7, 2, 31, 3];
      var calls = 0;
      while (!(uneven.step(batches[calls++ % batches.length]) as bool)) {
        check(calls < maxSteps, 'Uneven batches must converge');
      }
      cases['${entry.key}/${incremental ? 'incremental' : 'full'}'] = {
        'oneUnit': geometry(oneUnit),
        'oneShot': geometry(oneShot),
        'uneven': geometry(uneven.result),
      };
    }
  }
  return cases;
}

Map<String, Object> oracle() {
  final engine = ConstellationLayoutEngine(newIndex: BruteForceIndex.new);
  final cases = <String, Object>{};
  final sites = <String>{};
  replayExistingLayoutFixtures((fixture, site, input, legacy) {
    sites.add(site);
    cases[fixture] = {
      'site': site,
      'full': geometry(finish(engine.start(null, input))),
      'legacy': geometry(legacy),
    };
  });
  return {'fixtures': cases, 'sites': sites.toList()};
}

class InputReads {
  final byField = <String, int>{};
  void read(String field) => byField.update(field, (n) => n + 1);
  ObservedMap<V> map<V>(String field, Map<String, V> values) {
    byField[field] = 0;
    return ObservedMap(values, () => read(field));
  }
  ObservedSet set(String field, Set<String> values) {
    byField[field] = 0;
    return ObservedSet(values, () => read(field));
  }
  ObservedList list(String field, List<String> values) {
    byField[field] = 0;
    return ObservedList(values, () => read(field));
  }
  int get total => byField.values.fold(0, (total, count) => total + count);
}

class ObservedMap<V> extends MapBase<String, V> {
  ObservedMap(this.delegate, this.onRead);
  final Map<String, V> delegate;
  final void Function() onRead;
  int visitedKeys = 0;
  @override
  int get length => delegate.length;
  @override
  V? operator [](Object? key) {
    onRead();
    return delegate[key];
  }
  @override
  void operator []=(String key, V value) => delegate[key] = value;
  @override
  void clear() => delegate.clear();
  @override
  V? remove(Object? key) => delegate.remove(key);
  @override
  Iterable<String> get keys sync* {
    for (final id in delegate.keys) {
      onRead();
      visitedKeys++;
      yield id;
    }
  }
}

class ObservedSet extends SetBase<String> {
  ObservedSet(this.delegate, this.onRead);
  final Set<String> delegate;
  final void Function() onRead;
  int visitedKeys = 0;
  @override
  int get length => delegate.length;
  @override
  Iterator<String> get iterator => observedKeys.iterator;
  Iterable<String> get observedKeys sync* {
    for (final id in delegate) {
      onRead();
      visitedKeys++;
      yield id;
    }
  }
  @override
  bool contains(Object? value) {
    onRead();
    return delegate.contains(value);
  }
  @override
  bool add(String value) => delegate.add(value);
  @override
  String? lookup(Object? value) {
    onRead();
    return delegate.lookup(value);
  }
  @override
  bool remove(Object? value) => delegate.remove(value);
  @override
  Set<String> toSet() => Set.of(this);
}

class ObservedList extends ListBase<String> {
  ObservedList(this.delegate, this.onRead);
  final List<String> delegate;
  final void Function() onRead;
  @override
  int get length => delegate.length;
  @override
  set length(int value) => delegate.length = value;
  @override
  String operator [](int index) {
    onRead();
    return delegate[index];
  }
  @override
  void operator []=(int index, String value) => delegate[index] = value;
}

class ObservedIndex extends BruteForceIndex {
  int operations = 0;
  @override
  void insert(String id, LRect rect) {
    operations++;
    super.insert(id, rect);
  }
  @override
  bool remove(String id) {
    operations++;
    return super.remove(id);
  }
  @override
  List<String> queryOverlaps(LRect rect, {String? exceptId}) {
    operations++;
    return super.queryOverlaps(rect, exceptId: exceptId);
  }
}

Map<String, Object> deferred() {
  final input = syntheticLayoutInput(1000);
  final baselineEngine = ConstellationLayoutEngine(newIndex: BruteForceIndex.new);
  final previous = finish(baselineEngine.start(null, input));
  final cases = <String, Object>{};
  for (final incremental in [false, true]) {
    final reads = InputReads();
    final sizes = reads.map('nodeSizes', input.nodeSizes);
    final requests = reads.map('satelliteRequestIdsByAuthor', {
      for (final entry in input.satelliteRequestIdsByAuthor.entries)
        entry.key: reads.list('satellites/${entry.key}', entry.value),
    });
    final automatic = reads.set('automaticKeptPeerIds', input.automaticKeptPeerIds);
    final people = reads.set('pinnedPersonIds', input.pinnedPersonIds);
    final pinnedRequests = reads.set('pinnedRequestIds', input.pinnedRequestIds);
    final support = reads.set('supportPersonIds', input.supportPersonIds);
    int visits() => sizes.visitedKeys + requests.visitedKeys +
        automatic.visitedKeys + people.visitedKeys +
        pinnedRequests.visitedKeys + support.visitedKeys;
    final index = ObservedIndex();
    final engine = ConstellationLayoutEngine(newIndex: () => index);
    final job = engine.start(
      incremental ? previous : null,
      withLayoutChanges(
        input,
        paths: (
          depth: reads.map('paths.depth', input.paths.depth),
          derived: reads.map('paths.derived', input.paths.derived),
          parent: reads.map('paths.parent', input.paths.parent),
          parentTier: reads.map('paths.parentTier', input.paths.parentTier),
          attributed: reads.set('paths.attributed', input.paths.attributed),
          keep: reads.set('paths.keep', input.paths.keep),
          ring: reads.set('paths.ring', input.paths.ring),
        ),
        sizes: sizes,
        requests: requests,
        automatic: automatic,
        pinnedPeople: people,
        pinnedRequests: pinnedRequests,
        support: support,
        egoRequests: reads.set('egoOwnRequestIds', input.egoOwnRequestIds),
        authors: reads.map('requestAuthorById', input.requestAuthorById),
        footprints: reads.map('footprints', input.footprints),
        prior: (
          positions: reads.map<ConstellationPoint>('priorHints.positions', previous.positions),
          ring: reads.map<int>('priorHints.ring', previous.ring),
          viewportClass: input.viewportClass,
        ),
        anchors: reads.map('anchorByNodeId', {
          ...input.anchorByNodeId, 'p0': layoutAnchor(4, -4),
        }),
      ),
    );
    final startVisits = visits();
    final startOperations = index.operations;
    final startInputReads = Map.of(reads.byField);
    final before = unfinishedResultAccess(job);
    final zeroFinished = job.step(0);
    final zeroVisits = visits();
    final zeroOperations = index.operations;
    final zeroInputReads = Map.of(reads.byField);
    final result = finish(job);
    cases[incremental ? 'incremental' : 'full'] = {
      'startVisits': startVisits,
      'startOperations': startOperations,
      'startInputReads': startInputReads,
      'zeroFinished': zeroFinished,
      'zeroVisits': zeroVisits,
      'zeroOperations': zeroOperations,
      'zeroInputReads': zeroInputReads,
      'unfinishedResult': before,
      'completedNodes': result.positions.length,
      'totalVisits': visits(),
      'totalInputReads': reads.total,
    };
  }
  return cases;
}

Map<String, Object> cancellation() {
  final engine = ConstellationLayoutEngine(newIndex: BruteForceIndex.new);
  final input = syntheticLayoutInput(100);
  final previous = finish(engine.start(null, input));
  final published = geometry(previous);
  final publishedJson = jsonEncode(published);
  final originalInput = jsonEncode(layoutGeometry(
    computeConstellationPlacedLayout(input: input),
  ));
  final next = withLayoutChanges(
    input,
    anchors: {
      ...input.anchorByNodeId,
      'p0': layoutAnchor(8, 8),
    },
  );
  var totalUnits = 0;
  final reference = engine.start(previous, next);
  while (!(reference.step(1) as bool)) {
    check(++totalUnits < maxSteps, 'Incremental reference must converge');
  }
  totalUnits++;
  check(totalUnits > 4, 'Planning and placement must yield between units');
  final checkpoints = {1, totalUnits ~/ 4, totalUnits ~/ 2, totalUnits - 1};
  final attempts = <Object>[];
  for (final checkpoint in checkpoints) {
    final abandoned = engine.start(previous, next);
    for (var unit = 0; unit < checkpoint; unit++) {
      check(!(abandoned.step(1) as bool), 'Cancellation occurs before completion');
      check(jsonEncode(geometry(previous)) == publishedJson,
          'Unfinished job mutated the previous result');
    }
    final access = unfinishedResultAccess(abandoned);
    // LayoutJob's public contract has no cancel method. Cancellation stops
    // stepping and discards the job; only a completed result can be published.
    final replacementInput = withLayoutChanges(
      input,
      anchors: {...input.anchorByNodeId, 'p0': layoutAnchor(-8, -8)},
    );
    final replacement = finish(engine.start(previous, replacementInput));
    attempts.add({
      'checkpoint': checkpoint,
      'unfinishedResult': access,
      'publishedAfter': geometry(previous),
      'replacement': geometry(replacement),
      'expectedReplacement': geometry(finish(
        engine.start(previous, replacementInput),
        units: maxSteps,
      )),
      'inputAfter': jsonEncode(layoutGeometry(
        computeConstellationPlacedLayout(input: input),
      )),
    });
  }
  return {'published': published, 'inputBefore': originalInput, 'attempts': attempts};
}

Map<String, Object> benchmark() {
  final input = syntheticLayoutInput(1000);
  check(input.nodeSizes.length == 1000, 'Benchmark must contain exactly 1000 nodes');
  final engine = ConstellationLayoutEngine(newIndex: BruteForceIndex.new);
  final next = withLayoutChanges(
    input,
    anchors: {
      for (final anchor in input.anchorByNodeId.entries)
        anchor.key: layoutAnchor(-anchor.value.xUnits, -anchor.value.yUnits),
    },
  );
  // Warm both modes through JIT recompilation before timed samples. Three
  // passes still compiled hardKeepFreeNodes during incremental sample 2.
  // No measured sample is dropped; every startup and step duration is retained.
  dynamic previous;
  for (var warmup = 0; warmup < 10; warmup++) {
    previous = finish(engine.start(null, input));
    finish(engine.start(previous, next));
  }
  final cases = <Object>[];
  final scratch = Float64List(maxSteps ~/ 40);
  for (var sample = 0; sample < 3; sample++) {
    for (final incremental in [false, true]) {
      final watch = Stopwatch()..start();
      final job = engine.start(incremental ? previous : null, incremental ? next : input);
      watch.stop();
      final startMicros = watch.elapsedTicks * 1000000 / watch.frequency;
      var count = 0;
      bool done;
      do {
        watch.reset();
        watch.start();
        done = job.step(1);
        watch.stop();
        check(count < scratch.length, 'Measured job must converge');
        scratch[count++] = watch.elapsedTicks * 1000000 / watch.frequency;
      } while (!done);
      final result = job.result;
      // Unboxed storage: boxed timing lists would grow the old generation and
      // trigger collector pauses inside later timed units.
      final timings = Float64List.sublistView(scratch, 0, count).sublist(0);
      final workTimings = Float64List(count + 1)
        ..[0] = startMicros
        ..setRange(1, count + 1, timings);
      cases.add({
        'mode': incremental ? 'incremental' : 'full',
        'sample': sample,
        'n': input.nodeSizes.length,
        'completedNodes': result.positions.length,
        'unitsPerStep': 1,
        'startMicros': startMicros,
        'workMicros': workTimings,
        'workCount': workTimings.length,
        'maxWorkMicros': workTimings.reduce((a, b) => a > b ? a : b),
        'unitCount': timings.length,
        'unitMicros': timings,
        'maxUnitMicros': timings.reduce((a, b) => a > b ? a : b),
      });
    }
  }
  return {
    'n': 1000,
    'budgetMicros': 500,
    'clock': 'Stopwatch.elapsedTicks',
    'clockFrequency': Stopwatch().frequency,
    'cases': cases,
  };
}

void main(List<String> args) {
  final report = switch (args.single) {
    'stepping' => stepping(),
    'oracle' => oracle(),
    'deferred' => deferred(),
    'cancellation' => cancellation(),
    'benchmark' => benchmark(),
    _ => throw ArgumentError('Unknown layout probe ${args.single}'),
  };
  print(jsonEncode(report));
}
''';
