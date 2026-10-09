// Pure report contracts use the workspace's transitive test dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
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

List<Map<String, dynamic>> _readCases(File report) {
  expect(report.existsSync(), isTrue, reason: 'Benchmark report is absent');
  final json = jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
  expect(json['cases'], isA<List<dynamic>>());
  return (json['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
}

Map<String, dynamic> _recordedCase(
  List<Map<String, dynamic>> cases,
  String algorithm,
  String mode,
  int changed,
) {
  final matching = cases.where(
    (row) =>
        row['algorithm'] == algorithm &&
        row['n'] == 300 &&
        row['mode'] == mode &&
        row['changed'] == changed,
  );
  expect(
    matching,
    hasLength(1),
    reason: 'One recorded $algorithm N=300 $mode changed=$changed case',
  );
  return matching.single;
}

String _journalSection() {
  final journal = File(
    '${_repoRoot().path}/docs/plans/'
    'issue-235-constellation-interactive-journal.md',
  ).readAsStringSync();
  final sections = RegExp(
    r'^## UNIT U36\b[^\n]*\n[\s\S]*?(?=^## |$(?![\s\S]))',
    multiLine: true,
  ).allMatches(journal).map((match) => match.group(0)!);
  expect(sections, isNotEmpty, reason: 'No spatial index decision entry');
  // Validate only the latest appended U36 entry. An incomplete new entry
  // must not silently fall back to a historical decision table.
  return sections.last;
}

String? _algorithm(String text) {
  final normalized = text.toLowerCase().replaceAll(RegExp('[*_`-]'), ' ');
  final labels = [
    if (normalized.contains('brute')) 'brute_force',
    if (normalized.contains('sap') || normalized.contains('sweep')) 'sap',
    if (normalized.contains('grid')) 'grid',
    if (normalized.contains('aabb')) 'dynamic_aabb',
  ];
  return labels.length == 1 ? labels.single : null;
}

List<String> _cells(String line) => line
    .trim()
    .replaceAll(RegExp(r'^\||\|$'), '')
    .split('|')
    .map((cell) => cell.trim())
    .toList();

// Journal timing cells may carry their own units or inherit them from a header.
void _matchesReportTiming(String cell, String heading, num expectedUs) {
  final cleaned = cell.replaceAll(RegExp('[*`,]'), '');
  expect(
    cleaned,
    matches(RegExp(r'^\s*\d+(?:\.\d+)?\s*(?:ms|µs|μs|us)?\s*$')),
    reason: 'Decision table needs a measured timing, not a placeholder',
  );
  final value = double.parse(RegExp(r'\d+(?:\.\d+)?').firstMatch(cleaned)![0]!);
  final units = '$cleaned $heading'.toLowerCase();
  expect(units, matches(RegExp(r'ms|µs|μs|\bus\b')));
  expect(value, greaterThan(0));
  final factor = units.contains('ms') ? 1000.0 : 1.0;
  final number = RegExp(r'\d+(?:\.(\d+))?').firstMatch(cleaned)!;
  var resolution = factor;
  for (var i = 0; i < (number.group(1)?.length ?? 0); i++) {
    resolution /= 10;
  }
  expect(
    value * factor,
    closeTo(expectedUs, resolution / 2 + 1e-9),
    reason: 'Journal timings must match the recorded benchmark case',
  );
}

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

  group('Spatial index selection decision', () {
    test(
      'latest journal decision uses the recorded N=300 benchmark costs',
      () {
        final section = _journalSection();
        expect(section, contains('build/bench/spatial_index.json'));
        final report = File(
          '${_repoRoot().path}/packages/client/'
          'build/bench/spatial_index.json',
        );
        final cases = _readCases(report);
        final hash = sha256.convert(report.readAsBytesSync()).toString();
        expect(
          section.toLowerCase().replaceAll(RegExp('[*`]'), ''),
          matches(RegExp('sha-256:\\s*$hash')),
          reason: 'Identify the exact benchmark report used by the decision',
        );
        expect(section, matches(RegExp(r'30\s*%')));
        expect(section.toLowerCase(), contains('maintenance'));
        expect(
          section.toLowerCase(),
          matches(RegExp(r'full[^\n]*\band\b[^\n]*incremental')),
        );
        final measurements = <String, (num, num)>{};
        final changedCounts = <int>{};
        var decisionTables = 0;
        final lines = section.split('\n');
        for (var i = 0; i + 1 < lines.length; i++) {
          if (!lines[i].trimLeft().startsWith('|')) continue;
          final header = _cells(lines[i]);
          final separator = _cells(lines[i + 1]);
          if (!separator.every(
            (cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell),
          )) {
            continue;
          }
          final full = header.indexWhere(
            (cell) =>
                cell.toLowerCase().contains('full') &&
                !RegExp('win|gain|%').hasMatch(cell.toLowerCase()),
          );
          final incremental = header.indexWhere(
            (cell) =>
                cell.toLowerCase().contains('incremental') &&
                !RegExp('win|gain|%').hasMatch(cell.toLowerCase()),
          );
          final buildInvalidate = header.indexWhere(
            (cell) {
              final heading = cell.toLowerCase();
              return heading.contains('build') &&
                  RegExp('invalidat').hasMatch(heading) &&
                  !RegExp('win|gain|%').hasMatch(heading);
            },
          );
          final nColumn = header.indexWhere(
            (cell) => cell.toLowerCase().replaceAll(RegExp('[*`]'), '') == 'n',
          );
          final algorithmColumn = header.indexWhere(
            (cell) => RegExp(
              'algorithm|index|implementation',
            ).hasMatch(cell.toLowerCase()),
          );
          // Inspect every N=300 algorithm table, including contradictory tables
          // that omit a required timing column or format N with markdown.
          if (nColumn < 0 || algorithmColumn < 0) continue;
          final rows = <List<String>>[];
          for (
            var j = i + 2;
            j < lines.length && lines[j].trimLeft().startsWith('|');
            j++
          ) {
            final row = _cells(lines[j]);
            expect(row.length, header.length);
            final n = row[nColumn].replaceAll(RegExp('[*`]'), '').trim();
            if (int.tryParse(n) == 300) rows.add(row);
          }
          if (rows.isEmpty) continue;
          expect(
            full,
            greaterThanOrEqualTo(0),
            reason: 'N=300 needs full costs',
          );
          expect(
            incremental,
            greaterThanOrEqualTo(0),
            reason: 'N=300 needs incremental costs',
          );
          expect(
            buildInvalidate,
            greaterThanOrEqualTo(0),
            reason: 'N=300 decision must expose build plus invalidate costs',
          );
          final changedColumn = header.indexWhere(
            (cell) => cell.toLowerCase().contains('changed'),
          );
          expect(
            changedColumn,
            greaterThanOrEqualTo(0),
            reason: 'Identify which measured incremental workload was compared',
          );
          for (final column in [full, incremental, buildInvalidate]) {
            expect(
              header[column].toLowerCase(),
              matches(RegExp('total|including.*maintenance|end.to.end')),
              reason: 'Decision timings must explicitly include maintenance',
            );
          }
          for (final row in rows) {
            final algorithm = _algorithm(row[algorithmColumn]);
            expect(
              algorithm,
              isNotNull,
              reason: 'Unknown N=300 decision index',
            );
            expect(
              measurements.containsKey(algorithm),
              isFalse,
              reason: 'Exactly one unambiguous N=300 row per algorithm',
            );
            final changed = int.tryParse(row[changedColumn]);
            expect(changed, inInclusiveRange(1, 10));
            changedCounts.add(changed!);
            final fullUs = _nonnegativeTiming(
              _recordedCase(cases, algorithm!, 'full', 0),
              'totalUs',
            );
            final incrementalUs = _nonnegativeTiming(
              _recordedCase(cases, algorithm, 'incremental', changed),
              'totalUs',
            );
            final maintenanceRow = _recordedCase(
              cases,
              algorithm,
              'build_invalidate',
              0,
            );
            final buildInvalidateUs = _nonnegativeTiming(
              maintenanceRow,
              'totalUs',
            );
            final buildUs = _nonnegativeTiming(maintenanceRow, 'buildUs');
            final invalidateUs = _nonnegativeTiming(
              maintenanceRow,
              'invalidateUs',
            );
            expect(buildUs, greaterThan(0));
            expect(invalidateUs, greaterThan(0));
            expect(_nonnegativeTiming(maintenanceRow, 'queryUs'), isZero);
            expect(
              buildInvalidateUs,
              greaterThanOrEqualTo(buildUs + invalidateUs),
            );
            expect(fullUs, greaterThan(0));
            expect(incrementalUs, greaterThan(0));
            _matchesReportTiming(row[full], header[full], fullUs);
            _matchesReportTiming(
              row[incremental],
              header[incremental],
              incrementalUs,
            );
            _matchesReportTiming(
              row[buildInvalidate],
              header[buildInvalidate],
              buildInvalidateUs,
            );
            measurements[algorithm] = (fullUs, incrementalUs);
          }
          decisionTables++;
        }
        expect(decisionTables, 1, reason: 'One authoritative N=300 table');
        expect(
          changedCounts,
          hasLength(1),
          reason: 'Compare the same incremental workload for every index',
        );
        expect(
          measurements.keys,
          unorderedEquals(_algorithms),
          reason: 'N=300 decision table must compare all four indexes',
        );
        final baseline = measurements['brute_force']!;
        // U36 requires a 30% win in either full or incremental workloads.
        // The separate build/invalidate workload must be in the decision table.
        // Full/incremental totals already include their own maintenance, as
        // verified by the execution probe; adding this separate workload again
        // or requiring a third 30% win would change the plan's selection rule.
        // Eligibility uses the unrounded report values, not markdown rounding.
        final eligible = {
          for (final entry in measurements.entries)
            if (entry.key != 'brute_force' &&
                (entry.value.$1 <= baseline.$1 * 0.7 ||
                    entry.value.$2 <= baseline.$2 * 0.7))
              entry.key,
        };
        final choice = RegExp(
          r'^.*\b(?:choice|chosen|selected|retained)\b[^\n]*$',
          multiLine: true,
          caseSensitive: false,
        ).allMatches(section).map((match) => _algorithm(match[0]!)).nonNulls;
        expect(choice, hasLength(1), reason: 'State one explicit index choice');
        expect(
          choice.single,
          isIn(eligible.isEmpty ? {'brute_force'} : eligible),
          reason:
              'Keep brute force unless full OR incremental total cost wins '
              'by at least 30% at N=300; choose only a qualifying alternative',
        );
      },
    );
  });
}
