// tentura-xri1 (parent tentura-0cl.2.19): five WARNING diagnostics in server
// test files break the package-wide zero-warning contract exercised by
// server_package_analysis_test.dart. Focused regression (not a substitute for
// the full server test suite); package-wide WARNING gate via shared helpers.

import 'dart:io';

import 'package:test/test.dart';

import '../support/server_ci_lint_gate_harness.dart'
    show decodeAnalyzeDiagnostics, runDartAnalyzeSerialized;
import '../support/tentura_xri1_analyze_contract.dart';
import 'server_package_analysis_test.dart'
    show
        formatDiagnosticEntries,
        packageWideWarningDiagnosticEntries,
        runServerPackageAnalyze;

void main() {
  group('tentura-xri1 server test analyze warnings (parent tentura-0cl.2.19)', () {
    late final List<Map<String, dynamic>> packageDiagnostics;

    setUpAll(() {
      packageDiagnostics = _loadPackageAnalyzeDiagnostics();
    });

    test(
      'server_package_analysis_test package-wide gate has zero WARNINGs',
      () {
        final warnings = packageWideWarningDiagnosticEntries();
        expect(
          warnings,
          isEmpty,
          reason:
              'tentura-xri1: server_package_analysis_test requires package-wide '
              '`dart analyze .` with no WARNING diagnostics:\n'
              '${formatDiagnosticEntries(warnings)}',
        );
        final outcome = runServerPackageAnalyze();
        expect(
          outcome.exitCode,
          0,
          reason:
              'package-wide `dart analyze .` must exit 0 when WARNING-free '
              '(stdout: ${outcome.stdout}, stderr: ${outcome.stderr})',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'cited test paths have no tentura-xri1 WARNING codes in package analyze',
      () {
        final cited = _xri1CitedWarnings(packageDiagnostics);
        expect(
          cited,
          isEmpty,
          reason:
              'clear unused_element, unused_import, and '
              'unnecessary_non_null_assertion WARNINGs on cited paths '
              '(wire, remove, or replace — not // ignore):\n'
              '${cited.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'user_block_withdrawal_gate_pg_test has no unused_element WARNING in '
      'package analyze',
      () {
        final hits = _warningDiagnostics(
          packageDiagnostics,
          relative: kTenturaXri1WithdrawalGateRelative,
          code: 'unused_element',
        );
        expect(
          hits,
          isEmpty,
          reason:
              'clear unused_element WARNINGs on the withdrawal gate pg test:\n'
              '${hits.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'm0202 support has no unnecessary_non_null_assertion WARNING in '
      'package analyze',
      () {
        final hits = _warningDiagnostics(
          packageDiagnostics,
          relative: kTenturaXri1M0202SupportRelative,
          code: 'unnecessary_non_null_assertion',
        );
        expect(
          hits,
          isEmpty,
          reason:
              'clear unnecessary_non_null_assertion WARNINGs on m0202 support:\n'
              '${hits.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    test(
      'trust_publish_repository_mr_test has no unused_import WARNING in '
      'package analyze',
      () {
        final hits = _warningDiagnostics(
          packageDiagnostics,
          relative: kTenturaXri1TrustPublishMrRelative,
          code: 'unused_import',
        );
        expect(
          hits,
          isEmpty,
          reason:
              'clear unused_import WARNINGs on the trust publish mr test:\n'
              '${hits.join('\n')}',
        );
      },
      timeout: const Timeout(Duration(minutes: 12)),
    );

    group('cited paths do not suppress tentura-xri1 analyzer WARNING codes', () {
      for (final relative in kTenturaXri1CitedTestRelatives) {
        test(relative, () {
          expect(
            _xri1AnalyzerWarningSuppressions(relative),
            isEmpty,
            reason:
                'remove // ignore for unused_element, unused_import, or '
                'unnecessary_non_null_assertion on $relative instead of '
                'hiding debt:\n'
                '${_xri1AnalyzerWarningSuppressions(relative).join('\n')}',
          );
        });
      }
    });

    for (final relative in kTenturaXri1CitedTestRelatives) {
      test(
        '$relative has no ERROR or WARNING diagnostics in package analyze',
        () {
          final errors = _diagnosticsForRelative(
            packageDiagnostics,
            relativePath: relative,
            severity: 'ERROR',
          );
          final warnings = _diagnosticsForRelative(
            packageDiagnostics,
            relativePath: relative,
            severity: 'WARNING',
          );
          expect(
            errors,
            isEmpty,
            reason:
                'tentura-xri1 cited path $relative must stay ERROR-free in '
                'package analyze (CI runs this file, not skipped '
                'server_package_analysis xri1 cases):\n'
                '${errors.join('\n')}',
          );
          expect(
            warnings,
            isEmpty,
            reason:
                'tentura-xri1 cited path $relative must stay WARNING-free:\n'
                '${warnings.join('\n')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 12)),
      );
    }

    test(
      'user_block_withdrawal_gate_pg_test retains ban-wall targetWeight -1 '
      'expectations',
      () {
        final source = _serverTestSource(kTenturaXri1WithdrawalGateRelative);
        expect(
          source,
          contains('expect(await targetWeight(aliceId, bobId), -1);'),
          reason:
              'tentura-xri1 must not regress B1 ban-wall pg expectations while '
              'cleaning analyzer WARNINGs',
        );
        expect(
          source,
          isNot(contains('expect(await targetWeight(aliceId, bobId), 0);')),
          reason:
              'reverting targetWeight to 0 would fail the existing pg suite',
        );
      },
    );
  });
}

List<String> _xri1AnalyzerWarningSuppressions(String testRelativePath) {
  final source = _serverTestSource(testRelativePath);
  final hits = <String>[];
  final patterns = <RegExp>[
    RegExp(
      r'//\s*ignore:\s*(?:unused_element|unused_import|'
      r'unnecessary_non_null_assertion)',
    ),
    RegExp(
      r'ignore_for_file:\s*[^;\n]*(?:unused_element|unused_import|'
      r'unnecessary_non_null_assertion)',
    ),
  ];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final pattern in patterns) {
      if (pattern.hasMatch(line)) {
        hits.add('${testRelativePath}:${i + 1}: $line');
      }
    }
  }
  return hits;
}

List<Map<String, dynamic>> _loadPackageAnalyzeDiagnostics() {
  final serverRoot = _serverPackageRoot();
  final result = runDartAnalyzeSerialized(
    ['analyze', '--format=json', '.'],
    workingDirectory: serverRoot.path,
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
  return decodeAnalyzeDiagnostics(stdout);
}

List<String> _xri1CitedWarnings(List<Map<String, dynamic>> diagnostics) =>
    diagnostics
        .where((d) {
          if (d['severity'] != 'WARNING') {
            return false;
          }
          final code = d['code'] as String?;
          if (code == null ||
              !kTenturaXri1CitedWarningCodes.contains(code)) {
            return false;
          }
          final file = (d['location'] as Map?)?['file'] as String?;
          return _isXri1CitedTestFile(file);
        })
        .map(_formatDiagnostic)
        .toList();

bool _diagnosticOnServerRelative(String? absoluteFile, String relative) {
  if (absoluteFile == null || absoluteFile.isEmpty) {
    return false;
  }
  final normalized = absoluteFile.replaceAll(r'\', '/');
  return normalized.endsWith('/$relative');
}

List<String> _warningDiagnostics(
  List<Map<String, dynamic>> diagnostics, {
  required String relative,
  required String code,
}) {
  return _diagnosticsForRelative(
    diagnostics,
    relativePath: relative,
    severity: 'WARNING',
    code: code,
  );
}

List<String> _diagnosticsForRelative(
  List<Map<String, dynamic>> diagnostics, {
  required String relativePath,
  required String severity,
  String? code,
}) {
  return diagnostics
      .where((d) {
        if (d['severity'] != severity) {
          return false;
        }
        if (code != null && d['code'] != code) {
          return false;
        }
        final file = (d['location'] as Map?)?['file'] as String?;
        return _diagnosticOnServerRelative(file, relativePath);
      })
      .map(_formatDiagnostic)
      .toList();
}

String _formatDiagnostic(Map<String, dynamic> d) {
  final location = d['location'] as Map?;
  final line = location == null
      ? '?'
      : (location['range'] as Map?)?['start']?['line'];
  final file = location?['file'] ?? '?';
  final message =
      d['problemMessage']?.toString() ??
      d['message']?.toString() ??
      d['code']?.toString();
  return '$file:$line: $message';
}

bool _isXri1CitedTestFile(String? file) {
  if (file == null || file.isEmpty) {
    return false;
  }
  final normalized = file.replaceAll(r'\', '/');
  return kTenturaXri1CitedTestRelatives.any(
    (relative) => normalized.endsWith('/$relative'),
  );
}

String _serverTestSource(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
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
