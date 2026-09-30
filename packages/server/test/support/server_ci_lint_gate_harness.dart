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

/// Landing gates that spawn wrapped full-suite `dart test` runs (tentura-30e).
///
/// Each one skips itself when [kNestedLandingSuiteEnv] is set, so a nested
/// suite never re-enters a landing-check subprocess gate. Before tentura-30e
/// the fx7/j0q full-pg runners did not set it, so pg probe tests inside the
/// nested pg suite spawned their own wrapped pg subsets concurrently on the
/// shared Postgres (four nested "Failing tests:" blocks in one outer run).
const k30eReentrantLandingCheckRelativePaths = [
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_u6e_landing_check_test.dart',
  'test/architecture/tentura_fx7_landing_check_test.dart',
  'test/architecture/tentura_j0q_landing_check_test.dart',
];

/// Env flag that re-entrant landing gates and subprocess-spawning tests skip on.
const kNestedLandingSuiteEnv = 'TENTURA_U6E_NESTED_SUITE';

/// Env var carrying how many landing-suite subprocess levels are above us.
const kNestedLandingSuiteDepthEnv = 'TENTURA_NESTED_LANDING_SUITE_DEPTH';

/// A landing gate may nest at most one full-suite subprocess level.
const maxNestedLandingSuiteDepth = 1;

/// Environment for a nested landing-suite subprocess: marks it nested so
/// re-entrant gates skip, and refuses to stack beyond
/// [maxNestedLandingSuiteDepth].
Map<String, String> nestedLandingSuiteChildEnvironment(Directory nestedTmp) {
  final env = Platform.environment;
  final depth = int.tryParse(env[kNestedLandingSuiteDepthEnv] ?? '') ?? 0;
  if (depth >= maxNestedLandingSuiteDepth ||
      env[kNestedLandingSuiteEnv] == 'true') {
    throw StateError(
      'refusing to nest a landing suite subprocess at depth ${depth + 1} '
      '(max $maxNestedLandingSuiteDepth)',
    );
  }
  return {
    ...env,
    'DART_SUPPRESS_ANALYTICS': 'true',
    'TMPDIR': nestedTmp.path,
    // The suite includes the acceptance test that launches this process.
    kNestedLandingSuiteEnv: 'true',
    kNestedLandingSuiteDepthEnv: '${depth + 1}',
  };
}

/// Child environment for the nested full-pg landing runners (fx7/j0q).
Map<String, String> nestedPgLandingSuiteChildEnvironment(Directory nestedTmp) =>
    nestedLandingSuiteChildEnvironment(nestedTmp);

/// Wrapper argv for the nested non-pg landing suite (u6e/pl4).
List<String> nonPgNestedLandingDartTestArgs({required String timeout}) => [
  '--timeout',
  timeout,
  '--',
  'dart',
  'test',
  '--exclude-tags',
  'pg',
];

/// Wrapper argv for the nested full-pg landing suite (fx7/j0q).
const _pgNestedLandingDartTestArgs = [
  '--timeout',
  '30m',
  '--',
  'dart',
  'test',
  '--tags',
  'pg',
  '--exclude-tags',
  'mr',
];

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
      nonPgNestedLandingDartTestArgs(timeout: '20m'),
      workingDirectory: server.path,
      environment: nestedLandingSuiteChildEnvironment(nestedTmp),
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
      nonPgNestedLandingDartTestArgs(timeout: '30m'),
      workingDirectory: server.path,
      environment: nestedLandingSuiteChildEnvironment(nestedTmp),
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

/// Runs the exact tentura-50o / tentura-fx7 bead pg acceptance command.
CommandOutcome runFx7AcceptancePgLanding() {
  return _runNestedPgLandingSuite(
    'tentura-fx7-pg-nested-',
    childEnvironment: nestedPgLandingSuiteChildEnvironment,
  );
}

/// Runs the exact tentura-acz / tentura-j0q bead pg acceptance command.
CommandOutcome runJ0qAcceptancePgLanding() {
  return _runNestedPgLandingSuite(
    'tentura-j0q-pg-nested-',
    childEnvironment: nestedPgLandingSuiteChildEnvironment,
  );
}

/// Full `dart test --tags pg --exclude-tags mr` run for fx7/j0q landing gates,
/// serialized via [runWithNestedPgLandingSuiteLock] and marked nested via
/// [childEnvironment].
CommandOutcome _runNestedPgLandingSuite(
  String tmpPrefix, {
  required Map<String, String> Function(Directory nestedTmp) childEnvironment,
}) {
  final wrapper = testCleanupWrapperFromServerPackage();
  final server = serverPackageRoot();
  // A full pg suite writes several GB of dart_test kernel files into TMPDIR.
  // Keep them on disk (.dart_tool), not on the RAM tmpfs (/tmp): tmpfs
  // pressure with a full swap makes mmap page faults fail and unrelated
  // processes die with SIGBUS (tentura-5zq).
  final nestedTmp = Directory(
    '${server.path}/.dart_tool',
  ).createTempSync(tmpPrefix);
  try {
    return runWithNestedPgLandingSuiteLock(() {
      final result = Process.runSync(
        wrapper.path,
        _pgNestedLandingDartTestArgs,
        workingDirectory: server.path,
        environment: childEnvironment(nestedTmp),
      );
      return (
        exitCode: result.exitCode,
        stdout: result.stdout as String,
        stderr: result.stderr as String,
      );
    });
  } finally {
    nestedTmp.deleteSync(recursive: true);
  }
}

File testCleanupWrapperFromServerPackage() {
  final server = serverPackageRoot();
  final candidates = [
    File('${server.path}/../../scripts/run_with_test_cleanup.sh'),
    File(
      '${repoRootFromServerPackage().path}/scripts/run_with_test_cleanup.sh',
    ),
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

/// Relative to [serverPackageRoot] — the tentura-8u7 bead landing harness
/// re-checked by tentura-3i0m on the alloy/tentura-8u7 trial merge.
const k3i0mBeadAcceptanceTestPaths = [
  'test/architecture/tentura_pl4_di_acceptance_probe_test.dart',
  'test/architecture/tentura_8u7_landing_check_test.dart',
  'test/architecture/tentura_pl4_landing_check_test.dart',
  'test/architecture/tentura_amn_8u7_worktree_remediation_test.dart',
];

const _8u7TrialMergeRef = 'alloy/tentura-8u7';

/// Runs tentura-3i0m bead acceptance: the wrapped four-file dart test on a
/// detached worktree at alloy/tentura-8u7.
CommandOutcome run3i0mAcceptanceFourFileDartTestOn8u7TrialMerge() {
  return _runIn8u7TrialMergeWorktree((serverPackage, nestedTmp) {
    final wrapper = testCleanupWrapperFromServerPackage();
    final result = Process.runSync(
      wrapper.path,
      [
        '--timeout',
        '10m',
        '--',
        'dart',
        'test',
        ...k3i0mBeadAcceptanceTestPaths,
      ],
      workingDirectory: serverPackage.path,
      environment: {
        ...Platform.environment,
        'DART_SUPPRESS_ANALYTICS': 'true',
        'TMPDIR': nestedTmp.path,
      },
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  });
}

void _generateIgnoredSourcesIn8u7TrialMerge(Directory serverPackage) {
  final result = Process.runSync(
    'dart',
    ['run', 'build_runner', 'build', '-d'],
    workingDirectory: serverPackage.path,
    environment: {
      ...Platform.environment,
      'DART_SUPPRESS_ANALYTICS': 'true',
    },
  );
  if (result.exitCode != 0) {
    throw StateError(
      'build_runner build failed in 8u7 trial-merge worktree:\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
}

/// Alloy lands a bead on the trial merge of its branch with the landing
/// target, so merge the host HEAD (landing target) into the detached
/// alloy/tentura-8u7 checkout; a stale bead ref alone lacks later landings.
void _mergeLandingTargetInto8u7TrialMerge(
  Directory hostRepo,
  String worktreePath,
) {
  final head = Process.runSync(
    'git',
    ['rev-parse', 'HEAD'],
    workingDirectory: hostRepo.path,
  );
  if (head.exitCode != 0) {
    throw StateError('git rev-parse HEAD failed:\n${head.stderr}');
  }
  final merge = Process.runSync(
    'git',
    [
      '-c',
      'user.name=alloy-trial-merge',
      '-c',
      'user.email=alloy-trial-merge@localhost',
      'merge',
      '--no-edit',
      (head.stdout as String).trim(),
    ],
    workingDirectory: worktreePath,
  );
  if (merge.exitCode != 0) {
    throw StateError(
      'trial merge of host HEAD into $_8u7TrialMergeRef failed:\n'
      '${merge.stdout}\n${merge.stderr}',
    );
  }
}

typedef _8u7TrialMergeWorktreeRun<T> =
    T Function(
      Directory serverPackage,
      Directory nestedTmp,
    );

T _runIn8u7TrialMergeWorktree<T>(_8u7TrialMergeWorktreeRun<T> run) {
  final hostRepo = repoRootFromServerPackage();
  final worktreeParent = Directory.systemTemp.createTempSync(
    'tentura-3i0m-8u7-wt-',
  );
  final worktreePath = '${worktreeParent.path}/checkout';
  final nestedTmp = Directory.systemTemp.createTempSync(
    'tentura-3i0m-8u7-tmp-',
  );
  try {
    final add = Process.runSync(
      'git',
      ['worktree', 'add', '--detach', worktreePath, _8u7TrialMergeRef],
      workingDirectory: hostRepo.path,
    );
    if (add.exitCode != 0) {
      throw StateError(
        'git worktree add $_8u7TrialMergeRef failed:\n'
        '${add.stdout}\n${add.stderr}',
      );
    }
    _mergeLandingTargetInto8u7TrialMerge(hostRepo, worktreePath);
    final serverPackage = Directory('$worktreePath/packages/server');
    _generateIgnoredSourcesIn8u7TrialMerge(serverPackage);
    return run(serverPackage, nestedTmp);
  } finally {
    nestedTmp.deleteSync(recursive: true);
    Process.runSync(
      'git',
      ['worktree', 'remove', '--force', worktreePath],
      workingDirectory: hostRepo.path,
    );
    worktreeParent.deleteSync(recursive: true);
  }
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
