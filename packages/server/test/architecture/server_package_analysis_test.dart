// tentura-4wp (parent tentura-id8.5): package-wide `dart analyze` in
// packages/server — id8.5 touched lib paths stay warning-free; when the
// full package reports WARNINGs, they must be on cited outside-diff paths.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Lib paths touched by tentura-id8.5 (People seen GraphQL wiring + analyze
/// hygiene). Scoped checks must stay warning/error-free in package context.
const kId85TouchedLibRelatives = <String>[
  'lib/api/controllers/graphql/query/query_beacon_room.dart',
  'lib/api/controllers/graphql/query/query_invite_seed_prompt.dart',
  'lib/api/controllers/graphql/schema.dart',
  'lib/api/middleware/auth_middleware.dart',
];

/// Paths cited in tentura-4wp defect report (outside id8.5's four lib files).
const kTentura4wpDefectOutsideDiffRelatives = <String>[
  'analysis_options.yaml',
  'lib/app/sentry/sentry_init.dart',
  'lib/app/sentry/sentry_trace_propagation.dart',
  'lib/app/sentry/sentry_db_span.dart',
  'lib/app/sentry/sentry_request_tracing.dart',
  'lib/app/sentry/sentry_error_classifier.dart',
  'lib/app/sentry/auth_telemetry.dart',
  'lib/app/sentry/sentry_benign_filter.dart',
  'lib/app/sentry/sentry_request_context.dart',
  'lib/app/sentry/sentry_log_bridge.dart',
  'lib/app/sentry/sentry_event_scrub.dart',
];

Object get _skipNestedCleanupInCiDartTest {
  final env = Platform.environment;
  if (env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server' ||
      env['TENTURA_U6E_NESTED_SUITE'] == 'true') {
    return 'do not nest run_with_test_cleanup.sh inside CI dart test';
  }
  return false;
}

void main() {
  group('tentura-4wp server package analysis (parent tentura-id8.5)', () {
    test(
      'dart analyze on id8.5 touched lib paths exits 0 without WARNING or ERROR',
      () {
        final outcome = runDartAnalyzeOnId85TouchedLibPaths();
        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-id8.5 requires scoped '
              '`dart analyze` on the four touched lib files to exit 0\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
        expect(
          outcome.warnings,
          isEmpty,
          reason:
              'scoped analyze on id8.5 touched lib files must report no '
              'WARNING diagnostics:\n'
              '${formatDiagnosticEntries(outcome.warnings)}',
        );
        expect(
          outcome.errors,
          isEmpty,
          reason:
              'scoped analyze on id8.5 touched lib files must report no '
              'ERROR diagnostics:\n'
              '${formatDiagnosticEntries(outcome.errors)}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    test(
      'package-wide dart analyze . WARNING diagnostics stay off id8.5 touched libs and match cited outside-diff paths',
      () {
        final warnings = packageWideWarningDiagnosticEntries();

        final onTouched = warnings.where(
          (w) => isId85TouchedLibAnalyzePath(w.file),
        );
        expect(
          onTouched,
          isEmpty,
          reason:
              'tentura-4wp defect evidence: id8.5 touched lib files stay '
              'warning-free in package-wide `dart analyze .` even when exit '
              'code is 2\n'
              '${formatDiagnosticEntries(onTouched)}',
        );

        expect(
          warnings,
          isEmpty,
          reason:
              'tentura-4wp fixed: package-wide `dart analyze .` must report '
              'no WARNING diagnostics; historical outside-diff warnings '
              'must not be treated as acceptable:\n'
              '${formatDiagnosticEntries(warnings)}',
        );

        final outcome = runServerPackageAnalyze();

        expect(
          outcome.exitCode,
          0,
          reason:
              'tentura-4wp fixed: with checked-in options '
              '(plugins_in_inner_options ignored), package-wide '
              '`dart analyze .` exits 0 with no WARNING diagnostics on '
              'cited outside-diff paths or id8.5 touched lib files '
              '(stdout: ${outcome.stdout}, stderr: ${outcome.stderr})',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
      skip: _skipNestedCleanupInCiDartTest,
    );

    for (final relative in kId85TouchedLibRelatives) {
      test(
        'id8.5 touched lib $relative has no ERROR or WARNING in package analyze',
        () {
          expect(
            packageAnalyzeDiagnosticsForRelative(relative),
            isEmpty,
            reason:
                'tentura-id8.5 scoped analyze hygiene for $relative:\n'
                '${packageAnalyzeDiagnosticsForRelative(relative).join('\n')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 12)),
        skip: _skipNestedCleanupInCiDartTest,
      );
    }
  });
}

typedef PackageAnalyzeDiagnosticEntry = ({
  String file,
  int? line,
  String? code,
  String message,
});

/// Runs bare `dart analyze .` from [serverPackageRoot] (checked-in options).
({int exitCode, String stdout, String stderr}) runServerPackageAnalyze() {
  final result = Process.runSync(
    'dart',
    ['analyze', '.'],
    workingDirectory: serverPackageRoot().path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// `dart analyze` on [kId85TouchedLibRelatives] only (checked-in options).
({
  int exitCode,
  String stdout,
  String stderr,
  List<PackageAnalyzeDiagnosticEntry> warnings,
  List<PackageAnalyzeDiagnosticEntry> errors,
}) runDartAnalyzeOnId85TouchedLibPaths() {
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', ...kId85TouchedLibRelatives],
    workingDirectory: serverPackageRoot().path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  final warnings = stdout.isEmpty
      ? <PackageAnalyzeDiagnosticEntry>[]
      : parseDiagnosticEntries(stdout, severity: 'WARNING');
  final errors = stdout.isEmpty
      ? <PackageAnalyzeDiagnosticEntry>[]
      : parseDiagnosticEntries(stdout, severity: 'ERROR');
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
    warnings: warnings,
    errors: errors,
  );
}

List<PackageAnalyzeDiagnosticEntry> packageWideWarningDiagnosticEntries() =>
    _diagnosticEntries(severity: 'WARNING');

List<String> packageAnalyzeDiagnosticsForRelative(String relativePath) {
  final serverRoot = serverPackageRoot();
  final absolute = File('${serverRoot.path}/$relativePath').absolute.path;
  return _diagnosticEntries(
    severity: 'WARNING',
    filePath: absolute,
  ).map((e) => '${e.file}:${e.line}: ${e.message}').toList() +
      _diagnosticEntries(
        severity: 'ERROR',
        filePath: absolute,
      ).map((e) => '${e.file}:${e.line}: ${e.message}').toList();
}

bool isId85TouchedLibAnalyzePath(String absoluteFile) =>
    kId85TouchedLibRelatives.any(
      (relative) => _endsWithServerRelative(absoluteFile, relative),
    );

bool isTentura4wpCitedOutsideDiffAnalyzePath(String absoluteFile) =>
    kTentura4wpDefectOutsideDiffRelatives.any(
      (relative) => _endsWithServerRelative(absoluteFile, relative),
    );

bool _endsWithServerRelative(String absoluteFile, String relative) {
  final normalized = p.normalize(File(absoluteFile).absolute.path);
  final suffix = p.normalize(p.join(serverPackageRoot().path, relative));
  return normalized == suffix;
}

String formatDiagnosticEntries(Iterable<PackageAnalyzeDiagnosticEntry> entries) =>
    entries.map((e) => '${e.file}:${e.line}: ${e.message}').join('\n');

List<PackageAnalyzeDiagnosticEntry> _diagnosticEntries({
  required String severity,
  String? filePath,
}) {
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', '.'],
    workingDirectory: serverPackageRoot().path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  expect(
    stdout,
    isNotEmpty,
    reason:
        'dart analyze --format=json . must emit JSON (exit ${result.exitCode}); '
        'stderr: ${result.stderr}',
  );
  return parseDiagnosticEntries(stdout, severity: severity, filePath: filePath);
}

List<PackageAnalyzeDiagnosticEntry> parseDiagnosticEntries(
  String stdout, {
  required String severity,
  String? filePath,
}) {
  expect(
    stdout,
    isNotEmpty,
    reason: 'dart analyze --format=json must emit JSON',
  );

  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  return diagnostics
      .where((d) {
        if (d['severity'] != severity) {
          return false;
        }
        if (filePath == null) {
          return true;
        }
        final location = d['location'] as Map?;
        final file = location?['file'] as String?;
        return file == filePath;
      })
      .map((d) {
        final location = d['location'] as Map?;
        final line = location == null
            ? null
            : (location['range'] as Map?)?['start']?['line'] as int?;
        final file = location?['file'] as String? ?? '?';
        final message =
            d['problemMessage']?.toString() ??
            d['message']?.toString() ??
            d['code']?.toString() ??
            '?';
        return (
          file: file,
          line: line,
          code: d['code']?.toString(),
          message: message,
        );
      })
      .toList();
}

Directory serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final envDart = File('$path/lib/env.dart');
    if (envDart.existsSync()) {
      return Directory(p.normalize(envDart.absolute.parent.parent.path));
    }
  }
  throw StateError('server package root not found');
}
