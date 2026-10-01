// tentura-j0q landing gate acceptance (trial merge tentura-acz)

import 'dart:io';

import 'package:test/test.dart';

/// Hasura isolation paths that must stay green for tentura-acz pg landing.
const kJ0qHasuraIsolationPgTestPaths = [
  'test/support/isolated_hasura_session_port_pg_test.dart',
  'test/api/beacon_admitted_helpers_hasura_test.dart',
  'test/api/beacon_access_hasura_test.dart',
  'test/api/beacon_hierarchy_hasura_parity_test.dart',
  'test/support/hasura_pg_jwt_keys_test.dart',
];

/// Trust-closure migration paths on the tentura-acz trial merge branch.
const kJ0qTrustClosurePgTestPaths = [
  'test/data/database/m0202_trust_ledger_pg_test.dart',
  'test/data/database/m0203_closure_schema_pg_test.dart',
  'test/data/database/m0203_closure_hasura_metadata_test.dart',
];

const _isolatedHasuraHarnessRelative =
    'test/support/isolated_hasura_session.dart';

void main() {
  group('tentura-j0q pg acceptance probe (trial merge tentura-acz)', () {
    test('j0q hasura isolation pg paths exist on disk', () {
      for (final path in kJ0qHasuraIsolationPgTestPaths) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'missing hasura isolation pg test $path',
        );
      }
    });

    test('j0q trust-closure pg paths exist on disk', () {
      for (final path in kJ0qTrustClosurePgTestPaths) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'missing trust-closure pg test $path',
        );
      }
    });

    test(
      'IsolatedHasuraSession port claim documents tentura-j0q cross-process lock contract',
      () {
        final source = File(_isolatedHasuraHarnessRelative).readAsStringSync();
        expect(
          source,
          contains('tentura-j0q'),
          reason:
              '$_isolatedHasuraHarnessRelative must reference tentura-j0q so '
              'Alloy tracks acz Hasura port isolation remediation',
        );
      },
    );

    test(
      'tentura-acz hasura isolation pg files run green under pg tag filter',
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
            ...kJ0qHasuraIsolationPgTestPaths,
          ],
          workingDirectory: _serverPackageRoot().path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'tentura-acz landing requires all hasura isolation pg files to pass '
              'under --tags pg\n'
              'stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 26)),
      tags: const ['pg'],
      skip: Platform.environment['TENTURA_U6E_NESTED_SUITE'] == 'true'
          ? 'do not nest a wrapped pg suite inside the u6e nested suite'
          : false,
    );

    test(
      'tentura-acz trust-closure pg files run green under pg tag filter',
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
            ...kJ0qTrustClosurePgTestPaths,
          ],
          workingDirectory: _serverPackageRoot().path,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'tentura-acz landing requires trust-closure pg files to pass '
              'under --tags pg\n'
              'stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 26)),
      tags: const ['pg'],
      skip: Platform.environment['TENTURA_U6E_NESTED_SUITE'] == 'true'
          ? 'do not nest a wrapped pg suite inside the u6e nested suite'
          : false,
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
