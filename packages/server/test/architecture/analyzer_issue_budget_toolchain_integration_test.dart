// Toolchain integration acceptance test, not a gate-semantics unit test.
// Requires installed Flutter and Dart SDKs with writable caches and dependencies.
// The real gates bootstrap missing generated sources and analyze whole packages.
// Fake analyzer output cannot detect an increase in actual checkout diagnostics.
@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

final _repoRoot = Directory('../..').absolute;

Map<String, int> _readBudgets(File file) {
  final rows = file
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .where((line) => !line.trimLeft().startsWith('#'));
  return {
    for (final row in rows)
      row.trim().split(RegExp(r'\s+')).first: int.parse(
        row.trim().split(RegExp(r'\s+')).last,
      ),
  };
}

String _gateOutput(ProcessResult result) {
  final lines = '${result.stdout}\n${result.stderr}'.trim().split('\n');
  return lines.skip(lines.length > 12 ? lines.length - 12 : 0).join('\n');
}

void main() {
  group('Analyzer issue ratchet with the local toolchain', () {
    test('baseline files only lower the captured budgets', () {
      const baselineFiles = [
        'analyze-baseline.txt',
        'custom-lint-baseline.txt',
      ];
      for (final filename in baselineFiles) {
        final currentBudgets = _readBudgets(
          File('${_repoRoot.path}/scripts/$filename'),
        );
        final capturedBudgets = _readBudgets(
          File('test/architecture/fixtures/issue_budgets/$filename'),
        );

        // Check every row, including scoped analyzer and server lint budgets.
        // Lower counts are allowed; additional unbounded rows are not.
        for (final budget in currentBudgets.entries) {
          expect(
            capturedBudgets,
            contains(budget.key),
            reason: '$filename must not add an uncaptured issue budget',
          );
          expect(
            budget.value,
            lessThanOrEqualTo(capturedBudgets[budget.key]!),
            reason: '$filename must not raise the ${budget.key} issue budget',
          );
        }
      }
    });

    // CI runs these same gates directly (scripts/check-analysis.sh), so the
    // Pipeline excludes the `toolchain` tag rather than analyse twice.
    test(
      'analyzer and custom lint gates pass within captured baseline budgets',
      () async {
        const gates = <String, List<String>>{
          'client analyzer': [
            'scripts/check-analyze-baseline.sh',
            'packages/client',
          ],
          'server analyzer': [
            'scripts/check-analyze-baseline.sh',
            'packages/server',
          ],
          'client custom lints': [
            'scripts/check-custom-lints.sh',
            'packages/client',
          ],
        };
        final exitCodes = <String, int>{};
        final diagnostics = <String>[];
        // Run analyzers sequentially; each gate inspects the real package.
        for (final gate in gates.entries) {
          final result = await Process.run(
            'bash',
            gate.value,
            workingDirectory: _repoRoot.path,
          );
          exitCodes[gate.key] = result.exitCode;
          diagnostics.add('${gate.key}:\n${_gateOutput(result)}');
        }

        expect(
          exitCodes,
          {for (final gate in gates.keys) gate: 0},
          reason: diagnostics.join('\n\n'),
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
      tags: ['toolchain'],
    );
  });
}
