// Runs the real client analyzer gate: fake diagnostics cannot catch issue
// growth in the checkout. Requires the installed Flutter SDK and dependencies.
@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

final _repoRoot = Directory('../..').absolute;

// Capture the budget before remediation so raising the ratchet cannot make
// this acceptance test pass without reducing the analyzer diagnostics.
const _maximumClientIssueBudget = 2098;

void main() {
  group('Client analyzer issue budget', () {
    test('the checked-in budget is not raised', () {
      final budgetRows =
          File(
            '${_repoRoot.path}/scripts/analyze-baseline.txt',
          ).readAsLinesSync().where(
            (line) => line.trim().startsWith('packages/client '),
          );
      expect(budgetRows, hasLength(1));
      final budget = int.parse(
        budgetRows.single.trim().split(RegExp(r'\s+')).last,
      );
      expect(
        budget,
        lessThanOrEqualTo(_maximumClientIssueBudget),
        reason: 'Fix client diagnostics instead of increasing analyzer debt.',
      );
    });

    // CI runs this gate directly (scripts/check-analysis.sh), so the Pipeline
    // excludes the `toolchain` tag rather than analyse the client twice.
    test(
      'real package analysis passes without raising the issue budget',
      () async {
        final result = await Process.run(
          'bash',
          ['scripts/check-analyze-baseline.sh', 'packages/client'],
          workingDirectory: _repoRoot.path,
        );
        final output = '${result.stdout}\n${result.stderr}';
        final lines = output.trim().split('\n');
        final tail = lines.skip(lines.length > 12 ? lines.length - 12 : 0);
        expect(
          result.exitCode,
          0,
          reason:
              'The real client analyzer must complete within its '
              'checked-in budget and report no errors.\n${tail.join('\n')}',
        );
        expect(
          output,
          contains('check-analyze-baseline: packages/client OK ('),
          reason:
              'The gate must confirm that actual diagnostics fit the budget.',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
      tags: ['toolchain'],
    );
  });
}
