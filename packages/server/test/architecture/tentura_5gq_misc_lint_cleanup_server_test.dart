// tentura-5gq (server items 5–6): test-support analyzer hygiene at cited paths.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show
        decodeAnalyzeDiagnostics,
        runDartAnalyzeSerialized,
        serverPackageRoot;

const _jwtKeysTestRelative = 'test/support/hasura_pg_jwt_keys_test.dart';
const _jwtDefaultPathProbeRelative =
    'test/support/hasura_pg_jwt_default_path_probe_test.dart';

const _server5gqJwtSupportRelatives = <String>[
  _jwtKeysTestRelative,
  _jwtDefaultPathProbeRelative,
];

/// Pre-fix `dart analyze --format=json .` on packages/server (bead filing tree).
const _serverPackageDartAnalyzeBaselineDiagnosticCount = 1881;

/// Pre-fix `dart analyze --format=json` on [_server5gqJwtSupportRelatives].
const _server5gqJwtSupportBaselineDiagnosticCount = 2;

const _serverPackageDartAnalyzePostFixDiagnosticCount =
    _serverPackageDartAnalyzeBaselineDiagnosticCount -
    _server5gqJwtSupportBaselineDiagnosticCount;

const _server5gqBeadSites = <({String relativePath, int lineOneBased, String code})>[
  (
    relativePath: _jwtKeysTestRelative,
    lineOneBased: 7,
    code: 'depend_on_referenced_packages',
  ),
  (
    relativePath: _jwtDefaultPathProbeRelative,
    lineOneBased: 10,
    code: 'unnecessary_lambdas',
  ),
];

void main() {
  group('tentura-5gq server misc lint cleanup', () {
    test(
      'items 5–6 JWT paths and server package dart analyze drop exactly two bead diagnostics',
      () {
        final pinnedHits = _beadLintHitsOnRelativePaths(
          relativePaths: _server5gqJwtSupportRelatives,
          beadSites: _server5gqBeadSites,
        );
        expect(
          pinnedHits,
          isEmpty,
          reason:
              'tentura-5gq server items 5–6: pinned bead diagnostics must be '
              'absent:\n${_formatHits(pinnedHits)}',
        );

        final scopedCount = _countDartAnalyzeDiagnosticsOnRelativePaths(
          _server5gqJwtSupportRelatives,
        );
        expect(
          scopedCount,
          0,
          reason:
              'tentura-5gq server: JWT test-support scoped dart analyze must '
              'drop from baseline $_server5gqJwtSupportBaselineDiagnosticCount '
              'to 0 (actual $scopedCount)',
        );

        final packageCount = _countDartAnalyzeDiagnosticsOnServerPackage();
        expect(
          packageCount,
          _serverPackageDartAnalyzePostFixDiagnosticCount,
          reason:
              'tentura-5gq server package dart analyze must drop by exactly '
              '$_server5gqJwtSupportBaselineDiagnosticCount from baseline '
              '$_serverPackageDartAnalyzeBaselineDiagnosticCount '
              '(post-fix $_serverPackageDartAnalyzePostFixDiagnosticCount, '
              'actual $packageCount)',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

int _countDartAnalyzeDiagnosticsOnServerPackage() {
  return _countDartAnalyzeDiagnosticsOnRelativePaths(['.']);
}

int _countDartAnalyzeDiagnosticsOnRelativePaths(List<String> relativePaths) {
  final server = serverPackageRoot();
  final result = runDartAnalyzeSerialized(
    ['analyze', '--format=json', ...relativePaths],
    workingDirectory: server.path,
  );
  final stdout = (result.stdout as String).trim();
  if (stdout.isEmpty) {
    throw StateError(
      'dart analyze must emit JSON (exit ${result.exitCode}); '
      'stderr: ${result.stderr}',
    );
  }
  return decodeAnalyzeDiagnostics(stdout).length;
}

List<({String relativePath, int lineOneBased, String code})>
    _beadLintHitsOnRelativePaths({
  required List<String> relativePaths,
  required List<({String relativePath, int lineOneBased, String code})>
      beadSites,
}) {
  final server = serverPackageRoot();
  final result = runDartAnalyzeSerialized(
    ['analyze', '--format=json', ...relativePaths],
    workingDirectory: server.path,
  );
  final stdout = (result.stdout as String).trim();
  if (stdout.isEmpty) {
    throw StateError(
      'dart analyze must emit JSON (exit ${result.exitCode}); '
      'stderr: ${result.stderr}',
    );
  }
  final diagnostics = decodeAnalyzeDiagnostics(stdout);
  final hits = <({String relativePath, int lineOneBased, String code})>[];
  for (final site in beadSites) {
    final absolute = File('${server.path}/${site.relativePath}').absolute.path;
    for (final d in diagnostics) {
      if (d['code'] != site.code) {
        continue;
      }
      final location = d['location'] as Map?;
      final file = location?['file'] as String?;
      if (!p.equals(p.normalize(file ?? ''), p.normalize(absolute))) {
        continue;
      }
      final line = (location?['range'] as Map?)?['start']?['line'] as int?;
      if (line == site.lineOneBased) {
        hits.add(site);
      }
    }
  }
  return hits;
}

String _formatHits(
  List<({String relativePath, int lineOneBased, String code})> hits,
) {
  return hits
      .map((h) => '${h.relativePath}:${h.lineOneBased}: ${h.code}')
      .join('\n');
}
