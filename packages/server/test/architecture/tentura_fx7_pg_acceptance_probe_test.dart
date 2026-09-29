// tentura-fx7 landing gate acceptance (trial merge tentura-50o)

import 'dart:io';

import 'package:test/test.dart';

/// Same ten paths as [k2noRegressionPgTestPaths] in tentura_2no landing gates.
const kFx7RegressionPgTestPaths = [
  'test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart',
  'test/domain/use_case/review_obligation_settlement_pg_test.dart',
  'test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart',
  'test/domain/use_case/help_offer_obligation_settlement_pg_test.dart',
  'test/domain/use_case/review_obligation_backfill_pg_test.dart',
  'test/domain/use_case/attention_reconciliation_pg_test.dart',
  'test/data/database/m0201_clamp_pg_test.dart',
  'test/data/repository/evaluation_repository_submit_atomic_pg_test.dart',
  'test/data/repository/evaluation_repository_review_status_pg_test.dart',
  'test/data/repository/trust_maintenance_test.dart',
];

/// Evaluation-era files that must be remediated off A18 stub placeholders.
const _fx7EvaluationRemediatedPaths = [
  'test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart',
  'test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart',
  'test/data/repository/evaluation_repository_submit_atomic_pg_test.dart',
  'test/data/repository/evaluation_repository_review_status_pg_test.dart',
];

void main() {
  group('tentura-fx7 pg acceptance probe (trial merge tentura-50o)', () {
    test('regression pg paths match tentura-50o landing enumeration', () {
      expect(kFx7RegressionPgTestPaths, hasLength(10));
      for (final path in kFx7RegressionPgTestPaths) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'missing regression pg test $path',
        );
      }
    });

    test(
      'tentura-50o regression evaluation pg tests are remediated past A18 stubs',
      () {
        for (final path in _fx7EvaluationRemediatedPaths) {
          final source = File(path).readAsStringSync();
          expect(
            source.contains('A18 stub'),
            isFalse,
            reason:
                '$path still documents A18 stub placeholders — '
                'replace with post-m0203 disposable-pg coverage (tentura-fx7)',
          );
          expect(
            RegExp(r"test\('.*is stubbed'").hasMatch(source),
            isFalse,
            reason:
                '$path still asserts stubbed UnimplementedError paths — '
                'finish tentura-50o pg landing remediation',
          );
        }
      },
    );

    test(
      'tentura-50o regression pg files run green under pg tag filter',
      () async {
        final wrapper = _testCleanupWrapper();
        final result = await Process.run(
          wrapper.path,
          [
            '--timeout',
            '25m',
            '--',
            'dart',
            'test',
            '--tags',
            'pg',
            ...kFx7RegressionPgTestPaths,
          ],
          workingDirectory: _serverPackageRoot().path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'tentura-50o landing requires all ten regression pg files to pass '
              'under --tags pg\n'
              'stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 26)),
    );
  });
}

File _testCleanupWrapper() {
  final serverRoot = _serverPackageRoot();
  final candidates = [
    File('${serverRoot.path}/../../scripts/run_with_test_cleanup.sh'),
    File('${serverRoot.parent.parent.path}/scripts/run_with_test_cleanup.sh'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('scripts/run_with_test_cleanup.sh not found');
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}
