@Tags(<String>['perf', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'perf_fixture_matrix.dart';
import 'perf_fixture_report_expectations.dart';

/// The perf suites take timings against one shared MeritRank service, so they
/// must be launched one at a time through the cleanup wrapper, pg-only suites
/// apart from the MeritRank ones. The runner script's `--print-plan` mode lists
/// the commands without running them; each line is `pg: <command>` or
/// `mr: <command>`.
void main() {
  const script = '../../scripts/perf/run_perf_suite.sh';

  Future<ProcessResult> run(List<String> args) =>
      Process.run('bash', [script, ...args]);

  Future<List<String>> planLines() async {
    final result = await run(['--print-plan']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = (result.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines, isNotEmpty);
    return lines;
  }

  final phase = RegExp('^(pg|mr): ');

  String suiteOf(String line) =>
      RegExp(r'test/perf/(\w+_test\.dart)').firstMatch(line)!.group(1)!;

  String source(String suite) => File('test/perf/$suite').readAsStringSync();

  final suites = Directory('test/perf')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('_test.dart'))
      .where(
        (n) => File(
          'test/perf/$n',
        ).readAsStringSync().startsWith(RegExp(r'(//.*\n)*@Tags\(\[.*perf')),
      )
      .toList();

  test('the runner script exists and is executable', () {
    final file = File(script);

    expect(file.existsSync(), isTrue);
    expect(file.statSync().mode & 0x49, isNonZero, reason: 'executable bit');
  });

  test('the plan has one wrapped command per perf suite file', () async {
    final lines = await planLines();

    expect(lines, hasLength(suites.length));
    for (final suite in suites) {
      expect(
        lines.where((l) => l.contains('test/perf/$suite')),
        hasLength(1),
        reason: suite,
      );
    }
  });

  test('every planned command goes through the test cleanup wrapper', () async {
    for (final line in await planLines()) {
      expect(line, contains('run_with_test_cleanup.sh'), reason: line);
      expect(line, contains('dart test'), reason: line);
    }
  });

  test(
    'every planned command selects the perf tag and runs serialised',
    () async {
      for (final line in await planLines()) {
        expect(line, contains('--tags perf'), reason: line);
        expect(line, contains('-j 1'), reason: line);
      }
    },
  );

  test('the plan does not start suites in the background', () async {
    final text = (await planLines()).join('\n');

    expect(text, isNot(contains('&')));
    expect(text, isNot(contains('xargs -P')));
  });

  group('pg and MeritRank phases', () {
    test('every planned command is labelled with its phase', () async {
      for (final line in await planLines()) {
        expect(line, matches(phase), reason: line);
      }
    });

    test('both a pg-only and a MeritRank phase are planned', () async {
      final lines = await planLines();

      expect(lines.where((l) => l.startsWith('pg: ')), isNotEmpty);
      expect(lines.where((l) => l.startsWith('mr: ')), isNotEmpty);
    });

    test('every pg-only command runs before any MeritRank command', () async {
      final labels = [
        for (final l in await planLines()) phase.firstMatch(l)!.group(1),
      ];

      expect(labels, contains('pg'));
      expect(labels, contains('mr'));
      expect(
        labels.lastIndexOf('pg'),
        lessThan(labels.indexOf('mr')),
        reason: 'phases: $labels',
      );
    });

    test('each phase command runs exactly one suite file in its own '
        'wrapper invocation', () async {
      for (final line in await planLines()) {
        expect(
          RegExp('run_with_test_cleanup.sh').allMatches(line),
          hasLength(1),
          reason: line,
        );
        expect(
          RegExp(r'test/perf/\w+_test\.dart').allMatches(line),
          hasLength(1),
          reason: line,
        );
      }
    });

    test('a suite is in the MeritRank phase exactly when it needs a '
        'MeritRank graph', () async {
      for (final line in await planLines()) {
        final text = source(suiteOf(line));
        final needsMeritRank =
            text.contains('createPgmer2Extension: true') ||
            text.contains('mr_edgelist(');

        expect(line.startsWith('mr: '), needsMeritRank, reason: line);
      }
    });

    test('a pg-only suite never touches the MeritRank graph', () async {
      for (final line in await planLines()) {
        if (!line.startsWith('pg: ')) continue;

        expect(source(suiteOf(line)), isNot(contains('mr_edgelist')));
        expect(
          source(suiteOf(line)),
          isNot(contains('requireNonEmptyMeritRankGraph')),
        );
      }
    });

    test('every MeritRank fixture suite verifies the graph is non-empty '
        'before it measures', () async {
      for (final line in await planLines()) {
        if (!line.startsWith('mr: ')) continue;
        final text = source(suiteOf(line));
        if (!text.contains('PerfFixture')) continue;

        final guard = text.indexOf('requireNonEmptyMeritRankGraph(');
        expect(guard, isNonNegative, reason: line);
        for (final measure in ['.record(', 'PerfRecorder(']) {
          final at = text.indexOf(measure);
          if (at < 0) continue;
          expect(
            guard,
            lessThan(at),
            reason: '$line: guard must come before $measure',
          );
        }
      }
    });

    test('the matrix reports are produced by one suite per phase', () async {
      final lines = await planLines();

      expect(
        lines.where(
          (l) =>
              l.startsWith('pg: ') &&
              source(suiteOf(l)).contains('PerfFixtureMatrix'),
        ),
        hasLength(1),
      );
      expect(
        lines.where(
          (l) =>
              l.startsWith('mr: ') &&
              source(suiteOf(l)).contains('PerfFixtureMatrix'),
        ),
        hasLength(1),
      );
    });
  });

  group('report output', () {
    test('the runner writes its reports to build/perf', () async {
      final result = await run(['--print-output-dir']);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim(), 'build/perf');
    });

    group('--check-reports', () {
      late Directory dir;

      setUp(() => dir = Directory.systemTemp.createTempSync('perf_runner_'));
      tearDown(() => dir.deleteSync(recursive: true));

      Future<void> writeAllReports() async {
        for (final c in PerfFixtureMatrix.cases) {
          await writeFullReport(dir, c);
        }
      }

      Future<ProcessResult> check() => run(['--check-reports', dir.path]);

      String output(ProcessResult r) => '${r.stdout}${r.stderr}';

      // Each `--check-reports` call is a `dart run` that compiles the checker
      // from scratch (~15 s). The script wiring is covered end to end by the
      // pass, absent-report and missing-directory cases; the report-content
      // cases call the checker's logic in process.
      List<String> missing() => PerfFixtureMatrix.missingReports(dir);

      test(
        'succeeds when every matrix fixture has a full JSON report',
        () async {
          await writeAllReports();

          final result = await check();

          expect(result.exitCode, 0, reason: output(result));
        },
      );

      test('fails and names the fixture whose report is absent', () async {
        await writeAllReports();
        final absent = PerfFixtureMatrix.cases.last;
        File('${dir.path}/${absent.name}.json').deleteSync();

        final result = await check();

        expect(result.exitCode, isNonZero);
        expect(output(result), contains(absent.name));
      });

      test('fails when a report file is empty', () async {
        await writeAllReports();
        final empty = PerfFixtureMatrix.cases.first;
        File('${dir.path}/${empty.name}.json').writeAsStringSync('');

        expect(missing(), contains(empty.name));
      });

      test('fails when a report is not JSON', () async {
        await writeAllReports();
        final broken = PerfFixtureMatrix.cases.first;
        File('${dir.path}/${broken.name}.json').writeAsStringSync('{not json');

        expect(missing(), contains(broken.name));
      });

      test('fails when a report only names its fixture', () async {
        await writeAllReports();
        final stub = PerfFixtureMatrix.cases.first;
        File('${dir.path}/${stub.name}.json').writeAsStringSync(
          jsonEncode({'fixture': stub.name}),
        );

        expect(missing(), contains(stub.name));
      });

      test('fails when a report recorded no attempts', () async {
        await writeAllReports();
        final idle = PerfFixtureMatrix.cases.first;
        await writeFullReport(dir, idle, attempts: 0);

        expect(missing(), contains(idle.name));
      });

      test('fails when a report lacks its fixture parameters', () async {
        await writeAllReports();
        final bare = PerfFixtureMatrix.cases.first;
        final file = File('${dir.path}/${bare.name}.json');
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        json['parameters'] = <String, Object?>{};
        file.writeAsStringSync(jsonEncode(json));

        expect(missing(), contains(bare.name));
      });

      test(
        'fails when a report names a different fixture than its file',
        () async {
          await writeAllReports();
          final a = PerfFixtureMatrix.cases.first;
          final b = PerfFixtureMatrix.cases.last;
          File('${dir.path}/${a.name}.json').writeAsStringSync(
            File('${dir.path}/${b.name}.json').readAsStringSync(),
          );

          expect(missing(), contains(a.name));
        },
      );

      test('fails on an empty output directory', () async {
        expect(missing(), isNotEmpty);
      });

      test('fails on an output directory that does not exist', () async {
        final result = await run(['--check-reports', '${dir.path}/absent']);

        expect(result.exitCode, isNonZero);
      });
    });
  });
}
