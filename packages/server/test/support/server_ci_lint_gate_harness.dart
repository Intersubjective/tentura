// Shared harness for tentura-5zq / tentura-olc server package lint gates.

import 'dart:convert';
import 'dart:io';

/// Relative to [serverPackageRoot].
const kOlcLandingCheckTestRelative =
    'test/architecture/tentura_olc_landing_check_test.dart';

const kOlcBeadAcceptanceTestName =
    'bead acceptance: wrapped check-custom-lints.sh packages/server exits 0';

/// Bead evidence: id8.5 / tentura-617.3 touched line (1-based editor line).
const k5zqCitedOutsideDiffRelative = 'lib/data/database/tentura_db.dart';

const k5zqCitedOutsideDiffLineOneBased = 187;

typedef CommandOutcome = ({int exitCode, String stdout, String stderr});

typedef PackageAnalyzeSummary = ({
  int exitCode,
  int errorCount,
  int warningCount,
  int infoCount,
  List<String> errorLines,
});

Directory serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final envDart = File('$path/lib/env.dart');
    if (envDart.existsSync()) {
      return Directory(envDart.absolute.parent.parent.path);
    }
  }
  throw StateError('server package root not found');
}

Directory repoRootFromServerPackage() {
  var dir = serverPackageRoot();
  while (!File('${dir.path}/scripts/check-custom-lints.sh').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  final script = File('${dir.path}/scripts/check-custom-lints.sh');
  if (!script.existsSync()) {
    throw StateError('repo root not found from ${serverPackageRoot().path}');
  }
  return dir.absolute;
}

File olcLandingCheckTestFile() {
  final server = serverPackageRoot();
  final candidate = File('${server.path}/$kOlcLandingCheckTestRelative');
  if (!candidate.existsSync()) {
    throw StateError(
      'missing ${candidate.path} — tentura-olc landing harness must live here',
    );
  }
  return candidate;
}

/// CI step: `bash scripts/check-custom-lints.sh packages/server` from repo root.
CommandOutcome runServerCiLintGateFromRepoRoot() {
  final repo = repoRootFromServerPackage();
  final result = Process.runSync(
    'bash',
    ['scripts/check-custom-lints.sh', 'packages/server'],
    workingDirectory: repo.path,
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

/// Alloy historical required check (fatal-on-warnings default for `dart analyze .`).
CommandOutcome runBareDartAnalyzeDotInServerPackage() {
  final server = serverPackageRoot();
  final result = Process.runSync(
    'dart',
    ['analyze', '.'],
    workingDirectory: server.path,
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

/// Same analyzer flags as [scripts/check-custom-lints.sh].
CommandOutcome runDartAnalyzeDotNoFatalWarningsInServerPackage() {
  final server = serverPackageRoot();
  final result = Process.runSync(
    'dart',
    ['analyze', '--no-fatal-warnings', '.'],
    workingDirectory: server.path,
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

/// Entry point tentura-olc bead acceptance must call at runtime.
CommandOutcome runOlcAcceptanceServerLintGate() => runServerCiLintGateFromRepoRoot();

PackageAnalyzeSummary summarizePackageWideDartAnalyze() {
  final server = serverPackageRoot();
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', '.'],
    workingDirectory: server.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  if (stdout.isEmpty) {
    return (
      exitCode: result.exitCode,
      errorCount: -1,
      warningCount: -1,
      infoCount: -1,
      errorLines: ['empty dart analyze --format=json stdout'],
    );
  }
  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  var errors = 0;
  var warnings = 0;
  var infos = 0;
  final errorLines = <String>[];
  for (final d in diagnostics) {
    final severity = d['severity'] as String? ?? '';
    switch (severity) {
      case 'ERROR':
        errors++;
        errorLines.add(_formatDiagnostic(d));
      case 'WARNING':
        warnings++;
      case 'INFO':
        infos++;
    }
  }
  return (
    exitCode: result.exitCode,
    errorCount: errors,
    warningCount: warnings,
    infoCount: infos,
    errorLines: errorLines,
  );
}

List<Map<String, dynamic>> diagnosticsOnServerRelativeLine(
  String relativePath,
  int lineOneBased,
) {
  final server = serverPackageRoot();
  final absolute = File('${server.path}/$relativePath').absolute.path;
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', '.'],
    workingDirectory: server.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  final stdout = (result.stdout as String).trim();
  if (stdout.isEmpty) {
    return [];
  }
  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  final lineZero = lineOneBased - 1;
  return diagnostics.where((d) {
    final location = d['location'] as Map?;
    final file = location?['file'] as String?;
    if (file != absolute) {
      return false;
    }
    final line = (location?['range'] as Map?)?['start']?['line'] as int?;
    return line == lineZero;
  }).toList();
}

String readCheckCustomLintsScriptFromRepo() {
  final repo = repoRootFromServerPackage();
  return File('${repo.path}/scripts/check-custom-lints.sh').readAsStringSync();
}

/// Runs the olc bead-acceptance test by name (runtime, not source substring).
CommandOutcome runOlcBeadAcceptanceDartTest() {
  final server = serverPackageRoot();
  final result = Process.runSync(
    'dart',
    [
      'test',
      kOlcLandingCheckTestRelative,
      '--plain-name',
      kOlcBeadAcceptanceTestName,
    ],
    workingDirectory: server.path,
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

String _formatDiagnostic(Map<String, dynamic> d) {
  final location = d['location'] as Map?;
  final line = (location?['range'] as Map?)?['start']?['line'];
  final file = location?['file'] ?? '?';
  final message =
      d['problemMessage']?.toString() ??
      d['message']?.toString() ??
      d['code']?.toString() ??
      '?';
  return '$file:$line: $message';
}
