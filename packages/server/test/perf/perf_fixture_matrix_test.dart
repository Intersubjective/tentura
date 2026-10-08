@Tags(<String>['perf'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'perf_fixture_matrix.dart';
import 'perf_fixture_report_expectations.dart';
import 'perf_fixtures.dart';
import 'perf_report.dart';

Iterable<PerfFixtureCase> _family(PerfFixtureFamily family) =>
    PerfFixtureMatrix.cases.where((c) => c.family == family);

void main() {
  group('perf fixture matrix axes', () {
    test('visible users are 100, 300 and 1000', () {
      expect(PerfFixtureMatrix.visibleUsers, [100, 300, 1000]);
    });

    test('fallback-score populations are 0, 10, 100 and 1000 users', () {
      expect(PerfFixtureMatrix.fallbackUsers, [0, 10, 100, 1000]);
    });

    test('discoverable candidate counts are 100, 1k and 10k', () {
      expect(PerfFixtureMatrix.discoverableCandidates, [100, 1000, 10000]);
    });

    test('anchor counts are 0, 20 and 200', () {
      expect(PerfFixtureMatrix.anchors, [0, 20, 200]);
    });

    test('batch sizes are 1, 16 and 64', () {
      expect(PerfFixtureMatrix.batchSizes, [1, 16, 64]);
    });
  });

  group('perf fixture matrix cases', () {
    test('trust cases cover every visible-user count, sparse and dense', () {
      final names = _family(PerfFixtureFamily.trust).map((c) => c.name);

      expect(
        names,
        unorderedEquals([
          for (final v in [100, 300, 1000])
            for (final kind in ['sparse', 'dense']) 'v${v}_$kind',
        ]),
      );
    });

    test('trust case names are the names of the fixtures that seed them', () {
      final names = _family(PerfFixtureFamily.trust).map((c) => c.name);

      for (final v in PerfFixtureMatrix.visibleUsers) {
        expect(
          names,
          containsAll([
            PerfFixture.sparseTrust(visibleUsers: v).name,
            PerfFixture.denseTrust(visibleUsers: v).name,
          ]),
        );
      }
    });

    test('there is a reciprocal and a fallback-score case per fallback '
        'population size', () {
      final fallback = _family(PerfFixtureFamily.fallbackScore).toList();

      for (final kind in ['reciprocal', 'fallback']) {
        final ofKind = fallback.where(
          (c) => c.parameters['population'] == kind,
        );
        expect(
          ofKind.map((c) => c.parameters['fallbackUsers']),
          unorderedEquals(PerfFixtureMatrix.fallbackUsers),
          reason: kind,
        );
      }
    });

    test('there is one candidate case per candidate count', () {
      expect(
        _family(
          PerfFixtureFamily.candidates,
        ).map((c) => c.parameters['candidates']),
        unorderedEquals(PerfFixtureMatrix.discoverableCandidates),
      );
    });

    test('there is one anchor case per anchor count', () {
      expect(
        _family(PerfFixtureFamily.anchors).map((c) => c.parameters['anchors']),
        unorderedEquals(PerfFixtureMatrix.anchors),
      );
    });

    test('there is one batch case per batch size', () {
      expect(
        _family(PerfFixtureFamily.batches).map((c) => c.parameters['batch']),
        unorderedEquals(PerfFixtureMatrix.batchSizes),
      );
    });

    test('every case carries the parameters its report must echo', () {
      for (final c in PerfFixtureMatrix.cases) {
        expect(c.parameters, isNotEmpty, reason: c.name);
      }
    });

    test('every case name is unique and a valid report file name', () {
      final names = PerfFixtureMatrix.cases.map((c) => c.name).toList();

      expect(names.toSet().length, names.length);
      for (final name in names) {
        expect(
          () => PerfReport(fixture: name),
          returnsNormally,
          reason: name,
        );
      }
    });

    test('trust and fallback cases need MeritRank and run apart from the '
        'cases that do not', () {
      for (final c in PerfFixtureMatrix.cases) {
        final needsMeritRank =
            c.family == PerfFixtureFamily.trust ||
            c.family == PerfFixtureFamily.fallbackScore;
        if (needsMeritRank) expect(c.requiresMeritRank, isTrue, reason: c.name);
      }
      expect(
        PerfFixtureMatrix.cases.any((c) => !c.requiresMeritRank),
        isTrue,
        reason: 'pg-only fixtures must be separable from MeritRank ones',
      );
    });
  });

  group('perf fixture scenarios', () {
    const scenarioNames = [
      'aged_logs',
      'rejection_ratio',
      'multi_worker_tabs',
      'trust_churn',
      'failure_injection',
    ];

    PerfFixtureCase scenarioCase(String scenario) => _family(
      PerfFixtureFamily.scenarios,
    ).singleWhere((c) => c.parameters['scenario'] == scenario);

    test('cover aged logs, rejection ratios, multi-worker tabs, trust churn '
        'and failure injection', () {
      expect(PerfFixtureMatrix.scenarios, unorderedEquals(scenarioNames));
    });

    test('every scenario has exactly one matrix case that exercises it', () {
      for (final scenario in scenarioNames) {
        expect(
          _family(
            PerfFixtureFamily.scenarios,
          ).where((c) => c.parameters['scenario'] == scenario),
          hasLength(1),
          reason: scenario,
        );
      }
      expect(
        _family(PerfFixtureFamily.scenarios),
        hasLength(scenarioNames.length),
      );
    });

    test('each scenario case names the parameter that drives it', () {
      for (final scenario in scenarioNames) {
        final key = PerfFixtureMatrix.scenarioEvidenceKeys[scenario];

        expect(key, isNotNull, reason: scenario);
        expect(
          scenarioCase(scenario).parameters,
          contains(key),
          reason: scenario,
        );
      }
    });

    test('aged logs run against logs older than a day', () {
      expect(
        scenarioCase('aged_logs').parameters['logAgeDays'],
        isA<int>().having((d) => d, 'days', greaterThanOrEqualTo(1)),
      );
    });

    test('a rejection ratio is a share strictly between none and all', () {
      expect(
        scenarioCase('rejection_ratio').parameters['rejectionRatio'],
        isA<double>().having(
          (r) => r,
          'ratio',
          allOf(greaterThan(0), lessThan(1)),
        ),
      );
    });

    test('multi-worker tabs use at least two workers', () {
      expect(
        scenarioCase('multi_worker_tabs').parameters['workers'],
        isA<int>().having((w) => w, 'workers', greaterThanOrEqualTo(2)),
      );
    });

    test('trust churn rewrites at least one edge and needs MeritRank', () {
      final c = scenarioCase('trust_churn');

      expect(
        c.parameters['churnEdges'],
        isA<int>().having((e) => e, 'edges', greaterThanOrEqualTo(1)),
      );
      expect(c.requiresMeritRank, isTrue);
    });

    test('failure injection names the hook it injects through', () {
      expect(
        scenarioCase('failure_injection').parameters['failureHook'],
        isA<String>().having((h) => h, 'hook', isNotEmpty),
      );
    });

    test('scenario case names are valid and unique among all cases', () {
      final names = PerfFixtureMatrix.cases.map((c) => c.name).toList();

      expect(names.toSet(), hasLength(names.length));
      for (final c in _family(PerfFixtureFamily.scenarios)) {
        expect(c.name, startsWith('scenario_'));
      }
    });
  });

  group('missing report detection', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_matrix_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('an empty output directory is missing every fixture', () {
      expect(
        PerfFixtureMatrix.missingReports(dir),
        unorderedEquals(PerfFixtureMatrix.cases.map((c) => c.name)),
      );
    });

    test('a directory that does not exist is missing every fixture', () {
      final absent = Directory('${dir.path}/absent');

      expect(
        PerfFixtureMatrix.missingReports(absent),
        hasLength(PerfFixtureMatrix.cases.length),
      );
    });

    test('a fixture whose JSON was written is no longer missing', () async {
      final first = PerfFixtureMatrix.cases.first;
      await writeFullReport(dir, first);

      final missing = PerfFixtureMatrix.missingReports(dir);

      expect(missing, isNot(contains(first.name)));
      expect(missing, hasLength(PerfFixtureMatrix.cases.length - 1));
    });

    test('nothing is missing once every fixture has a report', () async {
      for (final c in PerfFixtureMatrix.cases) {
        await writeFullReport(dir, c);
      }

      expect(PerfFixtureMatrix.missingReports(dir), isEmpty);
    });

    test('a report that only names the fixture does not count as written', () {
      final first = PerfFixtureMatrix.cases.first;
      File('${dir.path}/${first.name}.json').writeAsStringSync(
        jsonEncode({'fixture': first.name}),
      );

      expect(PerfFixtureMatrix.missingReports(dir), contains(first.name));
    });

    test(
      'a report with no recorded attempts does not count as written',
      () async {
        final first = PerfFixtureMatrix.cases.first;
        await writeFullReport(dir, first, attempts: 0);

        expect(PerfFixtureMatrix.missingReports(dir), contains(first.name));
      },
    );

    test(
      'a report without the case parameters does not count as written',
      () async {
        final first = PerfFixtureMatrix.cases.first;
        final report = PerfReport(fixture: first.name)
          ..add(
            const PerfAttempt(
              latency: Duration(milliseconds: 1),
              execution: Duration(milliseconds: 1),
              failed: false,
              queryCount: 1,
              connectorRpcs: 0,
              cursorWait: Duration.zero,
              cursorHold: Duration.zero,
              connectionQueueTime: Duration.zero,
              txAge: Duration.zero,
              retryCount: 0,
              walBytes: 0,
            ),
          );
        await report.writeTo(dir);

        expect(PerfFixtureMatrix.missingReports(dir), contains(first.name));
      },
    );

    test('a report that is not JSON does not count as written', () {
      final first = PerfFixtureMatrix.cases.first;
      File('${dir.path}/${first.name}.json').writeAsStringSync('{not json');

      expect(PerfFixtureMatrix.missingReports(dir), contains(first.name));
    });

    test('a report filed under another fixture name does not count', () async {
      final a = PerfFixtureMatrix.cases.first;
      final b = PerfFixtureMatrix.cases.last;
      final written = await writeFullReport(dir, b);
      written.renameSync('${dir.path}/${a.name}.json');

      expect(PerfFixtureMatrix.missingReports(dir), contains(a.name));
    });

    test('an empty report file does not count as written', () {
      final first = PerfFixtureMatrix.cases.first;
      File('${dir.path}/${first.name}.json').writeAsStringSync('');

      expect(PerfFixtureMatrix.missingReports(dir), contains(first.name));
    });
  });
}
