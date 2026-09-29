// Shared harness for tentura-7qx client single-bead flutter analyze gates.

import 'dart:convert';
import 'dart:io';

/// Checked-in contract the tentura-7qx fix must add (see docs/contracts/*).
const k7qxClientBeadFlutterAnalyzeContractRelative =
    'docs/contracts/client-bead-flutter-analyze-gate.json';

typedef CommandOutcome = ({int exitCode, String stdout, String stderr});

typedef FlutterAnalyzeSummary = ({
  int exitCode,
  int errorCount,
  int warningCount,
  int infoCount,
  String issuesFoundLine,
});

Directory clientPackageRoot() {
  for (final path in const ['.', '../../packages/client']) {
    final pubspec = File('$path/pubspec.yaml');
    if (pubspec.existsSync()) {
      final nameLine = pubspec.readAsLinesSync().firstWhere(
        (line) => line.startsWith('name:'),
        orElse: () => '',
      );
      if (nameLine.contains('tentura')) {
        return Directory(pubspec.absolute.parent.path);
      }
    }
  }
  throw StateError('client package root not found');
}

Directory repoRootFromClientPackage() {
  var dir = clientPackageRoot();
  while (!File('${dir.path}/scripts/check-custom-lints.sh').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  final script = File('${dir.path}/scripts/check-custom-lints.sh');
  if (!script.existsSync()) {
    throw StateError('repo root not found from ${clientPackageRoot().path}');
  }
  return dir.absolute;
}

File clientBeadFlutterAnalyzeContractFile() =>
    File(
      '${repoRootFromClientPackage().path}/'
      '$k7qxClientBeadFlutterAnalyzeContractRelative',
    );

Map<String, dynamic> loadClientBeadFlutterAnalyzeContract() {
  final file = clientBeadFlutterAnalyzeContractFile();
  if (!file.existsSync()) {
    throw StateError('missing ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<String> beadScopedAnalyzeTargetsRelativeToClientPackage(
  Map<String, dynamic> contract,
) {
  final raw =
      (contract['beadScopedFlutterAnalyzeTargets'] as List?)?.cast<String>() ??
      const [];
  return raw
      .map(
        (path) => path.startsWith('packages/client/')
            ? path.substring('packages/client/'.length)
            : path,
      )
      .toList(growable: false);
}

/// Runs the contract-declared bead gate: `flutter analyze` on scoped targets
/// only (never package-wide `.`).
CommandOutcome runBeadScopedFlutterAnalyzeFromContract(
  Map<String, dynamic> contract,
) {
  final runner = Map<String, dynamic>.from(
    contract['beadGateRunner'] as Map? ?? const {},
  );
  final executable = runner['executable'] as String? ?? 'flutter';
  if (executable != 'flutter') {
    throw StateError('beadGateRunner must use flutter analyze');
  }
  final subcommand = runner['subcommand'] as String? ?? 'analyze';
  final targets = beadScopedAnalyzeTargetsRelativeToClientPackage(contract);
  if (targets.isEmpty) {
    throw StateError('beadScopedFlutterAnalyzeTargets must be non-empty');
  }
  if (targets.contains('.') || targets.any((t) => t == '.')) {
    throw StateError('bead gate must not analyze package root "."');
  }
  final client = clientPackageRoot();
  final result = Process.runSync(
    executable,
    [subcommand, ...targets],
    workingDirectory: client.path,
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

CommandOutcome runBareFlutterAnalyzeDotInClientPackage() {
  final client = clientPackageRoot();
  final result = Process.runSync(
    'flutter',
    ['analyze', '.'],
    workingDirectory: client.path,
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

CommandOutcome runFlutterAnalyzeWithPackageWidePrFlagsFromContract(
  Map<String, dynamic> contract,
) {
  final whenNeeded = Map<String, dynamic>.from(
    contract['packageWideFlutterAnalyzeWhenNeeded'] as Map? ?? const {},
  );
  final args =
      (whenNeeded['args'] as List?)?.cast<String>() ??
      const ['--no-fatal-warnings', '--no-fatal-infos', '.'];
  final client = clientPackageRoot();
  final result = Process.runSync(
    whenNeeded['executable'] as String? ?? 'flutter',
    ['analyze', ...args],
    workingDirectory: client.path,
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

FlutterAnalyzeSummary summarizeBareFlutterAnalyzeDot() {
  final outcome = runBareFlutterAnalyzeDotInClientPackage();
  final combined = '${outcome.stdout}\n${outcome.stderr}';
  final summary = summarizeDartAnalyzeJsonDot();
  return (
    exitCode: outcome.exitCode,
    errorCount: summary.errorCount,
    warningCount: summary.warningCount,
    infoCount: summary.infoCount,
    issuesFoundLine: _issuesFoundLine(combined),
  );
}

FlutterAnalyzeSummary summarizeDartAnalyzeJsonDot() {
  final client = clientPackageRoot();
  final result = Process.runSync(
    'dart',
    ['analyze', '--format=json', '.'],
    workingDirectory: client.path,
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
      issuesFoundLine: '',
    );
  }
  final payload = jsonDecode(stdout) as Map<String, dynamic>;
  final diagnostics =
      (payload['diagnostics'] as List).cast<Map<String, dynamic>>();
  var errors = 0;
  var warnings = 0;
  var infos = 0;
  for (final d in diagnostics) {
    switch (d['severity'] as String? ?? '') {
      case 'ERROR':
        errors++;
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
    issuesFoundLine: '',
  );
}

String _issuesFoundLine(String combinedOutput) {
  final match = RegExp(
    r'(\d+) issues found\.',
  ).firstMatch(combinedOutput);
  if (match == null) {
    return '';
  }
  return '${match.group(1)} issues found.';
}
