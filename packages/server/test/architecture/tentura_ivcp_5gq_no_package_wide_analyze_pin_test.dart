// tentura-ivcp: 5gq server gate must scope to JWT bead paths, not package-wide count.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show
        decodeAnalyzeDiagnostics,
        runDartAnalyzeSerialized,
        serverPackageRoot;

const _fiveGqServerTestRelative =
    'test/architecture/tentura_5gq_misc_lint_cleanup_server_test.dart';

const _ivcpProbeRelative =
    'test/architecture/tentura_ivcp_5gq_no_package_wide_analyze_pin_test.dart';

const _jwtKeysTestRelative = 'test/support/hasura_pg_jwt_keys_test.dart';
const _jwtDefaultPathProbeRelative =
    'test/support/hasura_pg_jwt_default_path_probe_test.dart';

const _server5gqJwtSupportRelatives = <String>[
  _jwtKeysTestRelative,
  _jwtDefaultPathProbeRelative,
];

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
  group('tentura-ivcp 5gq server analyze gate scoping', () {
    late String fiveGqSource;

    setUp(() {
      final server = serverPackageRoot();
      fiveGqSource = File('${server.path}/$_fiveGqServerTestRelative')
          .readAsStringSync();
    });

    test(
      '5gq server test does not pin package-wide dart analyze to an exact count',
      () {
        expect(
          fiveGqPackageWideExactCountAssertion(fiveGqSource),
          isFalse,
          reason:
              'tentura-ivcp: the 5gq server gate must not assert an exact '
              'package-wide `dart analyze .` diagnostic count (rename-resistant '
              'check on analyze scope and expect shape)',
        );
      },
    );

    test(
      '5gq server test still scopes JWT bead cleanup to cited relative paths',
      () {
        expect(fiveGqSource, contains('_server5gqJwtSupportRelatives'));
        expect(fiveGqSource, contains('_beadLintHitsOnRelativePaths'));
        expect(fiveGqSource, contains('_server5gqBeadSites'));
      },
    );

    test(
      'ambient drift: JWT bead criteria pass without coupling to package-wide count',
      () {
        final server = serverPackageRoot();

        final pinnedHits = _beadLintHitsOnRelativePaths(
          server: server,
          relativePaths: _server5gqJwtSupportRelatives,
          beadSites: _server5gqBeadSites,
        );
        expect(
          pinnedHits,
          isEmpty,
          reason:
              'tentura-ivcp drift probe: JWT bead pins must stay absent:\n'
              '${_formatHits(pinnedHits)}',
        );

        final jwtScopedCount = _countDartAnalyzeDiagnostics(
          server,
          _server5gqJwtSupportRelatives,
        );
        expect(
          jwtScopedCount,
          0,
          reason:
              'tentura-ivcp drift probe: JWT-scoped analyze must stay clean '
              '(actual $jwtScopedCount)',
        );

        final packageCount = _countDartAnalyzeDiagnostics(server, const ['.']);
        final probeOnlyCount = _countDartAnalyzeDiagnostics(
          server,
          [_ivcpProbeRelative],
        );
        final jwtPlusProbeCount = _countDartAnalyzeDiagnostics(
          server,
          [..._server5gqJwtSupportRelatives, _ivcpProbeRelative],
        );

        expect(
          packageCount,
          greaterThan(jwtScopedCount),
          reason:
              'tentura-ivcp drift probe: package-wide analyze must include '
              'diagnostics outside JWT bead paths (package $packageCount, '
              'JWT-scoped $jwtScopedCount)',
        );

        expect(
          jwtPlusProbeCount,
          greaterThan(jwtScopedCount),
          reason:
              'tentura-ivcp drift probe: this acceptance file adds analyze '
              'diagnostics outside the 5gq JWT paths without touching bead '
              'sites (JWT+probe $jwtPlusProbeCount, JWT-only $jwtScopedCount, '
              'probe-only $probeOnlyCount)',
        );

        // JWT-path gate criteria stay satisfied regardless of package-wide drift.
        final jwtCriteriaPass = pinnedHits.isEmpty && jwtScopedCount == 0;
        expect(jwtCriteriaPass, isTrue);

        // Simulated defect: a package-wide exact-count assertion would flip on
        // drift even while JWT criteria still pass.
        final couplesToPackageWideExactCount =
            fiveGqPackageWideExactCountAssertion(fiveGqSource);
        if (couplesToPackageWideExactCount) {
          expect(
            packageCount,
            isNot(equals(jwtScopedCount)),
            reason:
                'tentura-ivcp drift probe: package-wide count ($packageCount) '
                'already differs from JWT-scoped count ($jwtScopedCount) while '
                'JWT bead criteria still pass',
          );
        }

        expect(
          couplesToPackageWideExactCount,
          isFalse,
          reason:
              'tentura-ivcp: the 5gq gate must depend only on JWT path criteria '
              '(bead pins absent, JWT-scoped analyze clean), not on package-wide '
              'drift such as diagnostics from $_ivcpProbeRelative',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });
}

/// Detects any package-wide exact-count coupling in the 5gq server gate source,
/// including renamed constants or literals passed directly to [expect].
bool fiveGqPackageWideExactCountAssertion(String source) {
  final analyzesWholePackage = RegExp(
    r"_countDartAnalyzeDiagnosticsOnRelativePaths\(\s*\[\s*'\.'\s*\]\s*\)",
  ).hasMatch(source) ||
      source.contains('_countDartAnalyzeDiagnosticsOnServerPackage');

  final expectsPackageCount = RegExp(
    r'expect\s*\(\s*packageCount\s*,',
  ).hasMatch(source);

  final declaresPackageWideFrozenCount = RegExp(
    r'const\s+_\w*Package\w*DartAnalyze\w*DiagnosticCount\s*=',
  ).hasMatch(source);

  return (analyzesWholePackage && expectsPackageCount) ||
      declaresPackageWideFrozenCount;
}

int _countDartAnalyzeDiagnostics(Directory server, List<String> relativePaths) {
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
  required Directory server,
  required List<String> relativePaths,
  required List<({String relativePath, int lineOneBased, String code})>
      beadSites,
}) {
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
