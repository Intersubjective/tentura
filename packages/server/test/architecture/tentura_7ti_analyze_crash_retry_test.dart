// tentura-7ti (parent tentura-u6e): non-JSON `dart analyze --format=json`
// stdout (analyzer crash banners, signal text, truncated JSON) must be retried
// by the shared analyzer harness instead of reaching `jsonDecode` in the
// architecture gates. Empty stdout (SIGBUS) keeps being retried.
//
// Exhausted-retry contract at the consumer boundary: when the analyzer still
// emits non-JSON stdout after all attempts, the gates that parse it must fail
// with a controlled `TestFailure` that names `dart analyze` and quotes the
// offending output, never an uncaught `FormatException`/`TypeError` from
// `jsonDecode`. Each file decodes analyzer JSON through one guarded choke point.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show runDartAnalyzeSerialized, serverPackageRoot;
import 'server_package_analysis_test.dart' show parseDiagnosticEntries;

const _validJson = '{"version":1,"diagnostics":[]}';

typedef _FakeRun = ({String stdout, String stderr, int exitCode});

/// Crash outputs that are not JSON and do not mention dartbug.com, so retry
/// logic keyed on a single banner substring is not enough.
const _dartbugBanner = (
  stdout:
      'Unhandled exception:\nBad state: x\nPlease report this at dartbug.com\n',
  stderr: '',
  exitCode: 255,
);
const _signalText = (
  stdout: 'Segmentation fault (core dumped)\n',
  stderr: '',
  exitCode: 139,
);
const _serverCrashText = (
  stdout: 'The analysis server crashed unexpectedly.\n',
  stderr: 'Bus error\n',
  exitCode: 135,
);
const _truncatedJson = (
  stdout: '{"version":1,"diagnostics":[{"severity":"WARN',
  stderr: '',
  exitCode: 255,
);
const _emptyStdout = (stdout: '', stderr: 'SIGBUS\n', exitCode: 135);
const _ok = (stdout: _validJson, stderr: '', exitCode: 0);

void main() {
  group('tentura-7ti analyzer crash retry (parent tentura-u6e)', () {
    late Directory scratch;
    late Map<String, String> environment;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('tentura-7ti-');
      File(_join(scratch.path, 'invocations')).writeAsStringSync('0');
      environment = {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'PATH': '${scratch.path}:${Platform.environment['PATH'] ?? ''}',
        'TENTURA_7TI_DIR': scratch.path,
      };
    });

    tearDown(() {
      if (scratch.existsSync()) {
        scratch.deleteSync(recursive: true);
      }
    });

    /// Installs a fake `dart`: invocation `n` replays `runs[n - 1]`; later
    /// invocations replay the last entry.
    void installFakeDart(List<_FakeRun> runs) {
      for (var i = 0; i < runs.length; i++) {
        final n = i + 1;
        File(_join(scratch.path, 'out$n')).writeAsStringSync(runs[i].stdout);
        File(_join(scratch.path, 'err$n')).writeAsStringSync(runs[i].stderr);
        File(
          _join(scratch.path, 'code$n'),
        ).writeAsStringSync('${runs[i].exitCode}');
      }
      final script = File(_join(scratch.path, 'dart'))
        ..writeAsStringSync('''
#!/bin/sh
d="\$TENTURA_7TI_DIR"
n=\$(cat "\$d/invocations")
n=\$((n + 1))
echo "\$n" > "\$d/invocations"
k=\$n
[ "\$k" -gt ${runs.length} ] && k=${runs.length}
cat "\$d/out\$k"
cat "\$d/err\$k" >&2
exit \$(cat "\$d/code\$k")
''');
      final chmod = Process.runSync('chmod', ['+x', script.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
    }

    int invocations() => int.parse(
      File(_join(scratch.path, 'invocations')).readAsStringSync().trim(),
    );

    ProcessResult runJsonAnalyze() => runDartAnalyzeSerialized(
      ['analyze', '--format=json', '.'],
      workingDirectory: serverPackageRoot().path,
      environment: environment,
    );

    void expectValidJsonResult(ProcessResult result) {
      final stdout = (result.stdout as String).trim();
      expect(
        () => jsonDecode(stdout),
        returnsNormally,
        reason: 'final stdout must be valid JSON, got:\n$stdout',
      );
      expect(stdout, _validJson);
      expect(result.exitCode, 0);
    }

    final nonJsonCrashes = <String, _FakeRun>{
      'dartbug.com banner': _dartbugBanner,
      'signal text without dartbug.com': _signalText,
      'server-crashed text without dartbug.com': _serverCrashText,
      'truncated JSON': _truncatedJson,
    };

    for (final entry in nonJsonCrashes.entries) {
      test(
        'json analyze retries ${entry.key} and returns the valid JSON run',
        () {
          installFakeDart([entry.value, _ok]);

          final result = runJsonAnalyze();

          expectValidJsonResult(result);
          expect(invocations(), 2);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'json analyze gives up after three ${entry.key} runs and returns the last',
        () {
          installFakeDart([entry.value]);

          final result = runJsonAnalyze();

          expect(invocations(), 3, reason: 'bounded retries (maxAttempts = 3)');
          expect(result.stdout, entry.value.stdout);
          expect(result.stderr, entry.value.stderr);
          expect(result.exitCode, entry.value.exitCode);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }

    test(
      'json analyze recovers on the third attempt across mixed failure modes',
      () {
        installFakeDart([_emptyStdout, _truncatedJson, _ok]);

        final result = runJsonAnalyze();

        expectValidJsonResult(result);
        expect(invocations(), 3);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'empty stdout is still retried (SIGBUS case) and the valid run returned',
      () {
        installFakeDart([_emptyStdout, _ok]);

        final result = runJsonAnalyze();

        expectValidJsonResult(result);
        expect(invocations(), 2);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'empty stdout on every run gives up after three attempts, still empty',
      () {
        installFakeDart([_emptyStdout]);

        final result = runJsonAnalyze();

        expect(invocations(), 3);
        expect((result.stdout as String).trim(), isEmpty);
        expect(result.exitCode, _emptyStdout.exitCode);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'json analyze does not retry when the first run is valid JSON',
      () {
        installFakeDart([_ok]);

        final result = runJsonAnalyze();

        expectValidJsonResult(result);
        expect(invocations(), 1);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'plain-text analyze output is not treated as a crash',
      () {
        installFakeDart([
          (stdout: 'No issues found!\n', stderr: '', exitCode: 0),
        ]);

        final result = runDartAnalyzeSerialized(
          ['analyze', '.'],
          workingDirectory: serverPackageRoot().path,
          environment: environment,
        );

        expect((result.stdout as String).trim(), 'No issues found!');
        expect(invocations(), 1);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'plain-text analyze with non-empty crash-like text is not retried',
      () {
        installFakeDart([
          (stdout: '1 issue found.\n', stderr: '', exitCode: 3),
        ]);

        final result = runDartAnalyzeSerialized(
          ['analyze', '.'],
          workingDirectory: serverPackageRoot().path,
          environment: environment,
        );

        expect(result.exitCode, 3);
        expect(invocations(), 1);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group(
    'tentura-7ti JSON analyze consumers route through the retry helper',
    () {
      // Every architecture/support file that runs `dart analyze --format=json`
      // must obtain stdout from runDartAnalyzeSerialized (which retries crash
      // output) and never spawn `dart analyze` directly before jsonDecode.
      final testRoot = Directory(
        _join(serverPackageRoot().path, 'test'),
      );
      final jsonAnalyzeFiles = <File>[
        for (final entity in testRoot.listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith(
                'tentura_7ti_analyze_crash_retry_test.dart',
              ) &&
              entity.readAsStringSync().contains("'--format=json'"))
            entity,
      ];

      test('at least the known JSON analyze consumers are discovered', () {
        final names = jsonAnalyzeFiles.map((f) => _basename(f.path)).toSet();
        expect(
          names,
          containsAll(<String>[
            'server_package_analysis_test.dart',
            'server_ci_lint_gate_harness.dart',
          ]),
        );
      });

      for (final file in jsonAnalyzeFiles) {
        test('${_basename(file.path)} uses runDartAnalyzeSerialized only', () {
          final source = file.readAsStringSync();
          expect(
            source,
            contains('runDartAnalyzeSerialized('),
            reason: '${file.path} parses analyze JSON without the retry helper',
          );
          expect(
            RegExp(
              r'''Process\.(run|runSync|start)\(\s*['"]dart['"]''',
            ).hasMatch(source),
            isFalse,
            reason: '${file.path} spawns `dart` directly',
          );
        });
      }

      for (final file in jsonAnalyzeFiles) {
        test(
          '${_basename(file.path)} has a single guarded analyzer JSON decode',
          () {
            final name = _basename(file.path);
            final decodes = file
                .readAsLinesSync()
                .where((l) => !l.trimLeft().startsWith('//'))
                .where((l) => l.contains('jsonDecode('))
                .length;
            // Choke points: the shared harness and server_package_analysis_test
            // (parseDiagnosticEntries). Every other consumer must delegate.
            final allowed =
                const {
                  'server_ci_lint_gate_harness.dart',
                  'server_package_analysis_test.dart',
                }.contains(name)
                ? 1
                : 0;
            expect(
              decodes,
              allowed,
              reason:
                  '$name must not jsonDecode raw analyzer stdout outside '
                  'the single guarded decode (allowed: $allowed)',
            );
          },
        );
      }
    },
  );

  group('tentura-7ti exhausted retries fail with a controlled TestFailure', () {
    const crashStdouts = <String, String>{
      'dartbug.com banner':
          'Unhandled exception:\nBad state: x\nPlease report this at dartbug.com\n',
      'signal text': 'Segmentation fault (core dumped)\n',
      'truncated JSON': '{"version":1,"diagnostics":[{"severity":"WARN',
    };

    for (final entry in crashStdouts.entries) {
      test(
        'parseDiagnosticEntries on ${entry.key} throws TestFailure quoting it',
        () {
          expect(
            () => parseDiagnosticEntries(entry.value, severity: 'WARNING'),
            throwsA(
              isA<TestFailure>()
                  .having((e) => e.message, 'message', contains('dart analyze'))
                  .having(
                    (e) => e.message,
                    'message',
                    contains(entry.value.trim().split('\n').first),
                  ),
            ),
            reason:
                'non-JSON analyzer stdout must not escape as '
                'FormatException from jsonDecode',
          );
        },
      );
    }

    test(
      'parseDiagnosticEntries on valid JSON of the wrong shape throws TestFailure',
      () {
        for (final wrong in const ['[]', 'null', '{"version":1}']) {
          expect(
            () => parseDiagnosticEntries(wrong, severity: 'WARNING'),
            throwsA(isA<TestFailure>()),
            reason:
                'JSON without a diagnostics list ($wrong) must be a '
                'controlled failure, not a TypeError',
          );
        }
      },
    );

    test('parseDiagnosticEntries still parses valid analyzer JSON', () {
      expect(
        parseDiagnosticEntries(_validJson, severity: 'WARNING'),
        isEmpty,
      );
      final entries = parseDiagnosticEntries(
        '{"diagnostics":[{"severity":"WARNING","code":"c",'
        '"problemMessage":"m","location":{"file":"/a.dart",'
        '"range":{"start":{"line":3}}}}]}',
        severity: 'WARNING',
      );
      expect(entries.single.file, '/a.dart');
      expect(entries.single.message, 'm');
    });
  });
}

String _join(String dir, String name) => '$dir/$name';

String _basename(String path) => path.split('/').last;
