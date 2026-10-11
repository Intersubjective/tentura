// Pure report contracts use the workspace's transitive test dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

import 'fixtures/spatial_index_execution_probe.dart';

// Benchmark CLI contract: `dart run test/bench/spatial_index_bench.dart` writes
// build/bench/spatial_index.json in the client package. Each `cases` entry has
// algorithm, n, k, mode, changed, buildUs, invalidateUs, queryUs and totalUs.
// Modes are full, incremental (changed = 1..10), and build_invalidate.
// Each entry also records the fixture's distinct footprintSizes (width/height).
// This file validates the report; it does not implement or time an index.
// Benchmark-only test seam: exports benchmarkIndexFactories and
// runSpatialIndexBenchmark({indexFactories, nowMicros, onCaseStart, onCaseEnd,
// reportFile}). onCaseStart(algorithm, n, k, mode, changed) follows untimed
// preparation; onCaseEnd follows timing. The CLI invokes that same function.
// runSpatialIndexBenchmark returns Future<void>.
// Full = build N + N*K queries. Incremental = remove/reinsert M + M*K queries
// on a prebuilt N-item index. Build/invalidate = insert N then remove N.
const _algorithms = ['brute_force', 'sap', 'grid', 'dynamic_aabb'];
const _sizes = [100, 300, 600, 1000];

class _IndexIdentifiers extends RecursiveAstVisitor<void> {
  final names = <String>{};
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

class _BenchmarkInvocations extends RecursiveAstVisitor<void> {
  final names = <String>{};
  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}

Directory _repoRoot() {
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

num _nonnegativeTiming(Map<String, dynamic> row, String field) {
  expect(row[field], isA<num>(), reason: 'Missing measured $field: $row');
  final value = row[field] as num;
  expect(value.isFinite, isTrue);
  expect(value, greaterThanOrEqualTo(0));
  return value;
}

Future<ProcessResult> _runDart(File source, {bool compileOnly = false}) =>
    Process.run(
      RegExp(r'[/\\]dart(?:\.exe)?$').hasMatch(Platform.resolvedExecutable)
          ? Platform.resolvedExecutable
          : 'dart',
      [
        '--packages=${_repoRoot().path}/.dart_tool/package_config.json',
        if (compileOnly) ...[
          '--snapshot-kind=kernel',
          '--snapshot=${source.path}.dill',
        ],
        source.path,
      ],
      workingDirectory: '${_repoRoot().path}/packages/client',
    ).timeout(const Duration(minutes: 3));

void main() {
  group('Spatial index benchmark execution', () {
    test(
      'distinct candidate indexes execute workloads inside timed phases',
      () async {
        final client = Directory('${_repoRoot().path}/packages/client');
        final runner = File(
          '${client.path}/test/bench/spatial_index_bench.dart',
        );
        final probeSource = spatialIndexExecutionProbe(runner: runner.uri);
        expect(
          parseString(content: probeSource, throwIfDiagnostics: false).errors,
          isEmpty,
          reason: 'The test probe must be valid Dart source',
        );
        // Compile against a type-only stub so missing benchmark files cannot
        // mask errors in the generated execution harness.
        final compileDirectory = Directory.systemTemp.createTempSync(
          'spatial_probe_compile_',
        );
        addTearDown(() => compileDirectory.deleteSync(recursive: true));
        final stub = File('${compileDirectory.path}/benchmark_stub.dart')
          ..writeAsStringSync(spatialIndexBenchmarkCompileStub);
        final compileProbe = File('${compileDirectory.path}/probe.dart')
          ..writeAsStringSync(spatialIndexExecutionProbe(runner: stub.uri));
        final compilation = await _runDart(compileProbe, compileOnly: true);
        expect(
          compilation.exitCode,
          0,
          reason:
              'The test harness must compile before checking behavior: '
              '${compilation.stdout}\n${compilation.stderr}',
        );
        for (final name in [
          'sweep_and_prune_index.dart',
          'uniform_grid_index.dart',
          'dynamic_aabb_tree_index.dart',
        ]) {
          final candidate = File('${client.path}/test/bench/$name');
          expect(
            candidate.existsSync(),
            isTrue,
            reason: 'Missing benchmark-only implementation $name',
          );
          final identifiers = _IndexIdentifiers();
          parseString(
            content: candidate.readAsStringSync(),
          ).unit.accept(identifiers);
          expect(
            identifiers.names,
            isNot(contains('BruteForceIndex')),
            reason: 'Candidate must not inherit or delegate to brute force',
          );
        }
        expect(runner.existsSync(), isTrue);
        final main = parseString(content: runner.readAsStringSync())
            .unit
            .declarations
            .whereType<FunctionDeclaration>()
            .where((declaration) => declaration.name.lexeme == 'main');
        expect(main, hasLength(1));
        final invocations = _BenchmarkInvocations();
        main.single.functionExpression.body.accept(invocations);
        expect(
          invocations.names,
          contains('runSpatialIndexBenchmark'),
          reason: 'CLI must use the same benchmark exercised by the probe',
        );
        final temporary = Directory.systemTemp.createTempSync('spatial_probe_');
        addTearDown(() => temporary.deleteSync(recursive: true));
        final probe = File('${temporary.path}/probe.dart')
          ..writeAsStringSync(probeSource);
        final result = await _runDart(probe);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('Spatial index execution probe passed'));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
  group('Spatial index benchmark report', () {
    test(
      'a fresh run writes all index workloads including maintenance costs',
      () async {
        final client = Directory('${_repoRoot().path}/packages/client');
        final runner = File(
          '${client.path}/test/bench/spatial_index_bench.dart',
        );
        expect(
          runner.existsSync(),
          isTrue,
          reason:
              'The benchmark-only SAP, grid and dynamic AABB runner is absent',
        );
        final report = File('${client.path}/build/bench/spatial_index.json');
        final previous = report.existsSync() ? report.readAsBytesSync() : null;
        addTearDown(() {
          if (previous != null) {
            report.writeAsBytesSync(previous);
          }
        });
        if (report.existsSync()) report.deleteSync();

        final result = await _runDart(runner);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          report.existsSync(),
          isTrue,
          reason: 'Run must create fresh JSON',
        );
        final json =
            jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
        expect(json['cases'], isA<List<dynamic>>());
        final cases = (json['cases'] as List<dynamic>)
            .map((row) => row as Map<String, dynamic>)
            .toList();
        expect(cases, hasLength(_algorithms.length * _sizes.length * 12));

        for (final size in _sizes) {
          for (final algorithm in _algorithms) {
            for (final (mode, changed) in [
              ('full', 0),
              for (var changed = 1; changed <= 10; changed++)
                ('incremental', changed),
              ('build_invalidate', 0),
            ]) {
              final matching = cases.where(
                (row) =>
                    row['n'] == size &&
                    row['algorithm'] == algorithm &&
                    row['mode'] == mode &&
                    row['changed'] == changed,
              );
              expect(
                matching,
                hasLength(1),
                reason:
                    'Missing or duplicate $algorithm N=$size $mode $changed',
              );
              final row = matching.single;
              expect(
                row['k'],
                inInclusiveRange(60, 72),
                reason: 'Use approximately 66 layout candidates',
              );
              expect(row['footprintSizes'], isA<List<dynamic>>());
              final footprints = row['footprintSizes'] as List<dynamic>;
              expect(footprints.length, greaterThan(1));
              for (final footprint in footprints.cast<Map<String, dynamic>>()) {
                expect(footprint['width'], greaterThan(0));
                expect(footprint['height'], greaterThan(0));
              }
              expect(
                footprints.map(jsonEncode).toSet().length,
                greaterThan(1),
                reason: 'Use mixed node/label footprints, not identical points',
              );
              final build = _nonnegativeTiming(row, 'buildUs');
              final invalidate = _nonnegativeTiming(row, 'invalidateUs');
              final query = _nonnegativeTiming(row, 'queryUs');
              final total = _nonnegativeTiming(row, 'totalUs');
              expect(total, greaterThan(0));
              expect(total, greaterThanOrEqualTo(build + invalidate + query));
              expect(build, mode == 'incremental' ? isZero : greaterThan(0));
              expect(invalidate, mode == 'full' ? isZero : greaterThan(0));
              expect(
                query,
                mode == 'build_invalidate' ? isZero : greaterThan(0),
              );
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
}
