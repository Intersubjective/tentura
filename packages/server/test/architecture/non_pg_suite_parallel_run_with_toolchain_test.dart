// Acceptance run for the analyzer gates sharing a process with every other
// default-run suite. `analyzer_issue_budget_toolchain_integration_test` once
// reported a spurious extra server analyzer issue (or an analyzer crash) only
// when it ran inside a parallel server run, because another suite wrote files
// under packages/server while the analyzer was scanning it. Re-running the
// whole default selection, toolchain included, must pass repeatedly and leave
// the package tree exactly as it found it. Covers any suite, not a fixed list.
@Tags(['toolchain'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/package_tree_snapshot.dart';

/// Set for the inner runs so they skip this suite instead of recursing.
const _nestedRunMarker = 'TENTURA_NESTED_PARALLEL_RUN';

/// Opt-in: the check re-runs the whole default selection three times (well over
/// an hour on a busy machine), so it never runs as part of a plain
/// `dart test --exclude-tags pg`. Set to `1` to run the acceptance check.
const _optInVariable = 'TENTURA_RUN_PARALLEL_ACCEPTANCE';

const _consecutivePasses = 3;

bool get _isNestedRun => Platform.environment[_nestedRunMarker] == '1';

void main() {
  group('Default server run in parallel with the analyzer gates', () {
    test(
      'passes $_consecutivePasses times in a row without touching the '
      'package tree',
      () async {
        final before = snapshotPackageTree();

        for (var run = 1; run <= _consecutivePasses; run++) {
          final result = await Process.run(
            Platform.resolvedExecutable,
            [
              'test',
              '-j',
              '8',
              '--exclude-tags',
              'pg',
              '--reporter=failures-only',
            ],
            environment: {_nestedRunMarker: '1'},
          );
          final output = '${result.stdout}\n${result.stderr}';
          expect(
            result.exitCode,
            0,
            reason: 'parallel run $run of $_consecutivePasses failed:\n$output',
          );
          expect(
            changedPaths(before, snapshotPackageTree()),
            isEmpty,
            reason:
                'parallel run $run left files created or changed under '
                'packages/server; suites must write scratch output under '
                'Directory.systemTemp',
          );
        }
      },
      skip: _isNestedRun
          ? 'inner run of the parallel acceptance check'
          : Platform.environment[_optInVariable] == '1'
          ? false
          : 'set $_optInVariable=1 to re-run the whole default selection '
                '$_consecutivePasses times',
      timeout: const Timeout(Duration(minutes: 90)),
    );
  });
}
