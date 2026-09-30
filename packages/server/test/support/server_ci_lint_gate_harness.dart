// Shared harness for tentura-5zq / tentura-olc server package lint gates.

import 'dart:convert';
import 'dart:io';

/// Relative to [serverPackageRoot].
const kOlcLandingCheckTestRelative =
    'test/architecture/tentura_olc_landing_check_test.dart';

const kOlcBeadAcceptanceTestName =
    'bead acceptance: wrapped check-custom-lints.sh packages/server exits 0';

/// Relative to [serverPackageRoot].
const kU6eLandingCheckTestRelative =
    'test/architecture/tentura_u6e_landing_check_test.dart';

const kU6eBeadAcceptanceTestName =
    'bead acceptance: wrapped dart test --exclude-tags pg exits 0 (tentura-5zq landing)';

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

/// Runs `dart <args>` (an `analyze` invocation) under a per-checkout
/// `flock(1)` so the server package's analyzer gates never overlap.
///
/// `dart test` runs the architecture gates of one suite as concurrent
/// isolates, and each gate spawns its own analysis server. They all share the
/// checkout's tentura_lints plugin snapshot under `~/.dartServer/.plugin_manager`,
/// which the plugin manager rebuilds in place without a cross-process lock; a
/// server that has the old `plugin.aot` mapped then dies with SIGBUS
/// ("The analysis server crashed unexpectedly"). An external lock is needed:
/// `RandomAccessFile.lock` does not exclude isolates of the same process.
///
/// `dart analyze` always prints something (a JSON object or "No issues
/// found!"), so empty stdout means the analysis server died under full-suite
/// load rather than reporting diagnostics; such runs are retried.
ProcessResult runDartAnalyzeSerialized(
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
}) {
  const maxAttempts = 3;
  late ProcessResult result;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    result = _runUnderAnalyzeLock(
      'dart',
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    if ((result.stdout as String).trim().isNotEmpty) break;
  }
  return result;
}

ProcessResult _runUnderAnalyzeLock(
  String executable,
  List<String> args, {
  required String workingDirectory,
  Map<String, String>? environment,
}) {
  final lockFile = File(
    '${serverPackageRoot().path}/.dart_tool/dart_analyze_gate.lock',
  )..createSync(recursive: true);
  final hasFlock = Process.runSync('which', ['flock']).exitCode == 0;
  return hasFlock
      ? Process.runSync(
          'flock',
          [lockFile.path, executable, ...args],
          workingDirectory: workingDirectory,
          environment: environment,
        )
      : Process.runSync(
          executable,
          args,
          workingDirectory: workingDirectory,
          environment: environment,
        );
}

/// CI step: `bash scripts/check-custom-lints.sh packages/server` from repo root.
CommandOutcome runServerCiLintGateFromRepoRoot() {
  final repo = repoRootFromServerPackage();
  final result = _runUnderAnalyzeLock(
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
  final result = runDartAnalyzeSerialized(
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
  final result = runDartAnalyzeSerialized(
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
  final result = runDartAnalyzeSerialized(
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
      errorLines: [
        'empty dart analyze --format=json stdout '
            '(exit ${result.exitCode})',
        'stderr: ${result.stderr}',
      ],
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
  final result = runDartAnalyzeSerialized(
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

/// Runs tentura-u6e bead acceptance: full server non-pg suite via test cleanup wrapper.
CommandOutcome runU6eAcceptanceNonPgDartTest() {
  final wrapper = testCleanupWrapperFromServerPackage();
  final server = serverPackageRoot();
  final nestedTmp = Directory('${server.path}/.dart_tool').createTempSync(
    'tentura-u6e-nonpg-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '20m',
        '--',
        'dart',
        'test',
        '--exclude-tags',
        'pg',
      ],
      workingDirectory: server.path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
        // The suite includes the acceptance test that launches this process.
        'TENTURA_U6E_NESTED_SUITE': 'true',
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

/// Runs tentura-pl4 bead acceptance: full server non-pg suite via test cleanup wrapper.
CommandOutcome runPl4AcceptanceNonPgDartTest() {
  final wrapper = testCleanupWrapperFromServerPackage();
  final server = serverPackageRoot();
  final nestedTmp = Directory('${server.path}/.dart_tool').createTempSync(
    'tentura-pl4-nonpg-nested-',
  );
  try {
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '30m',
        '--',
        'dart',
        'test',
        '--exclude-tags',
        'pg',
      ],
      workingDirectory: server.path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
        // The suite includes the acceptance test that launches this process.
        'TENTURA_U6E_NESTED_SUITE': 'true',
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

/// Serializes the nested full-pg-suite landing acceptance runs per checkout.
///
/// The tentura-fx7 and tentura-j0q landing gates each nest a complete
/// `dart test --tags pg --exclude-tags mr` run. Many pg test files share the
/// same local Postgres cluster with fixed fixture ids (and cascade jobs such
/// as `BlockCascadeCase.runDue` process intents globally), so two nested pg
/// suites progressing through the same files in lockstep corrupt each other's
/// fixtures (observed: block_cascade_job_pg_test X8 cascade status,
/// forward_edge create_batch dedup unique violations). Disposable per-process
/// pg targets are unaffected, so probe subsets stay unlocked; only the
/// full-pg landing runners take this lock.
T runWithNestedPgLandingSuiteLock<T>(T Function() body) {
  final lockFile = File(
    '${serverPackageRoot().path}/.dart_tool/nested_pg_landing_suite.lock',
  )..createSync(recursive: true);
  final raf = lockFile.openSync(mode: FileMode.append);
  try {
    raf.lockSync(FileLock.blockingExclusive);
    return body();
  } finally {
    raf.closeSync();
  }
}

File testCleanupWrapperFromServerPackage() {
  final server = serverPackageRoot();
  final candidates = [
    File('${server.path}/../../scripts/run_with_test_cleanup.sh'),
    File('${repoRootFromServerPackage().path}/scripts/run_with_test_cleanup.sh'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('scripts/run_with_test_cleanup.sh not found');
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
