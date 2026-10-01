// tentura-3zd: static + behavioral contracts for Hasura pg fresh-checkout harness.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Env vars that may redirect where the subprocess loads repo dotenv from.
const kHasuraPgFreshCheckoutDotEnvPathEnvCandidates = <String>[
  'TENTURA_HASURA_PG_REPO_DOT_ENV',
  'TENTURA_HASURA_PG_FRESH_CHECKOUT_DOT_ENV',
  'TENTURA_TEST_REPO_DOT_ENV',
  'TENTURA_HASURA_PG_FRESH_CHECKOUT_REPO_ROOT',
];

const _kHideSuffixMarker = 'tentura50o_hide';

/// Removes // and /* */ comments and simple string literals for source analysis.
String stripDartCommentsAndStrings(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      i = source.indexOf('\n', i);
      if (i < 0) {
        break;
      }
      buffer.write('\n');
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      if (end < 0) {
        break;
      }
      i = end + 2;
      continue;
    }
    final char = source[i];
    if (char == "'" || char == '"') {
      final quote = char;
      i++;
      while (i < source.length) {
        if (source[i] == r'\' && i + 1 < source.length) {
          i += 2;
          continue;
        }
        if (source[i] == quote) {
          i++;
          break;
        }
        i++;
      }
      buffer.write(' ');
      continue;
    }
    if (source.startsWith("r'", i) || source.startsWith('r"', i)) {
      final quote = source[i + 1];
      i += 2;
      while (i < source.length && source[i] != quote) {
        i++;
      }
      if (i < source.length) {
        i++;
      }
      buffer.write(' ');
      continue;
    }
    buffer.write(char);
    i++;
  }
  return buffer.toString();
}

/// Any in-place hide/restore of the checkout `.env` anywhere in the harness library.
List<String> inPlaceRepoDotEnvRenameViolations(String harnessLibrarySource) {
  final code = stripDartCommentsAndStrings(harnessLibrarySource);
  final violations = <String>[];

  if (code.contains(_kHideSuffixMarker)) {
    violations.add('contains $_kHideSuffixMarker hide-rename suffix');
  }

  for (final match in RegExp(r'\.rename(?:Sync)?\s*\(').allMatches(code)) {
    final start = match.start;
    final contextStart = start < 240 ? 0 : start - 240;
    final contextEnd = match.end + 240 < code.length ? match.end + 240 : code.length;
    final window = code.substring(contextStart, contextEnd);
    final touchesCheckoutDotEnv = window.contains('.env') ||
        window.contains('dotEnv') ||
        window.contains('hiddenDotEnv') ||
        window.contains('repoRoot') ||
        window.contains('repoDotEnv');
    if (touchesCheckoutDotEnv) {
      violations.add(
        'rename call near checkout dotenv: ${window.replaceAll(RegExp(r'\s+'), ' ').trim()}',
      );
    }
  }

  return violations.toSet().toList();
}

/// Subprocess env must redirect dotenv loading without mutating the workspace tree.
bool harnessSubprocessEnvIsolatesRepoDotEnv(String harnessLibrarySource) {
  final code = stripDartCommentsAndStrings(harnessLibrarySource);
  if (inPlaceRepoDotEnvRenameViolations(harnessLibrarySource).isNotEmpty) {
    return false;
  }

  final dotEnvPathWired = kHasuraPgFreshCheckoutDotEnvPathEnvCandidates.any(
    (key) => _envMapAssignsKey(harnessLibrarySource, key),
  );

  final homeRedirect = _envMapAssignsKey(harnessLibrarySource, 'HOME');

  final copiesWorkspaceDotEnv = RegExp(
    r'dotEnv\.readAsString(?:Sync)?\s*\(|readAsString(?:Sync)?\s*\(\s*\)\s*;?',
  ).hasMatch(code) &&
      RegExp(r'writeAsString(?:Sync)?\s*\(|\.copy(?:Sync)?\s*\(').hasMatch(code) &&
      RegExp(r'createTemp\s*\(|Directory\.systemTemp').hasMatch(code);

  return dotEnvPathWired || (homeRedirect && copiesWorkspaceDotEnv);
}

bool _envMapAssignsKey(String harnessLibrarySource, String key) {
  return harnessLibrarySource.contains("env['$key']") ||
      harnessLibrarySource.contains('env["$key"]') ||
      harnessLibrarySource.contains("'$key':") ||
      harnessLibrarySource.contains('"$key":') ||
      harnessLibrarySource.contains("..['$key']") ||
      harnessLibrarySource.contains('..["$key"]');
}

File workspaceRepoDotEnvFile(String serverPackageRoot) {
  final repoRoot = p.normalize(p.join(serverPackageRoot, '../..'));
  return File(p.join(repoRoot, '.env'));
}

Future<void> restoreWorkspaceRepoDotEnvFromHideArtifacts(
  String serverPackageRoot,
) async {
  final dotEnv = workspaceRepoDotEnvFile(serverPackageRoot);
  if (dotEnv.existsSync()) {
    return;
  }
  final repoRoot = dotEnv.parent;
  for (final entity in repoRoot.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = p.basename(entity.path);
    if (name.startsWith('.env.') && name.contains('hide')) {
      await entity.rename(dotEnv.path);
      return;
    }
  }
}

Future<void> expectWorkspaceRepoDotEnvSurvivesHarnessSigkill({
  required String serverPackageRoot,
  required String workspaceRepoRoot,
  required Future<Process> Function() spawnHarnessRunner,
  Duration waitBeforeKill = const Duration(milliseconds: 500),
  File? readyMarkerFile,
  Duration readyMarkerTimeout = const Duration(seconds: 20),
}) async {
  final repoRoot = p.normalize(p.join(serverPackageRoot, '../..'));
  final dotEnv = File(p.join(repoRoot, '.env'));
  if (!dotEnv.existsSync()) {
    throw TestFailure(
      'workspace repo .env must exist for tentura-3zd SIGKILL probe',
    );
  }
  final bytesBefore = await dotEnv.readAsBytes();

  Process? proc;
  var dotEnvExistsAfterKill = false;
  List<int>? dotEnvBytesAfterKill;
  try {
    proc = await spawnHarnessRunner();
    if (readyMarkerFile != null) {
      // Prove the subprocess chain actually reached the code under test
      // (VM boot + package resolution for a nested `dart test` can exceed a
      // fixed delay) before killing -- otherwise the SIGKILL can land before
      // anything the harness does is reachable, and the probe passes
      // vacuously regardless of whether the fix is correct.
      final deadline = DateTime.now().add(readyMarkerTimeout);
      while (!readyMarkerFile.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure(
            'tentura-3zd SIGKILL probe: ready marker ${readyMarkerFile.path} '
            'never appeared within $readyMarkerTimeout -- the harness '
            'subprocess chain was never proven reachable, so this probe '
            'cannot validate the SIGKILL behavior it claims to',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    } else {
      await Future<void>.delayed(waitBeforeKill);
    }
    proc.kill(ProcessSignal.sigkill);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      // Expected after SIGKILL.
    }
    dotEnvExistsAfterKill = dotEnv.existsSync();
    if (dotEnvExistsAfterKill) {
      dotEnvBytesAfterKill = await dotEnv.readAsBytes();
    }
  } finally {
    proc?.kill(ProcessSignal.sigkill);
    await restoreWorkspaceRepoDotEnvFromHideArtifacts(serverPackageRoot);
  }

  expect(
    dotEnvExistsAfterKill,
    isTrue,
    reason:
        'SIGKILL mid _runFreshCheckoutDartTest must not leave workspace .env '
        'missing at ${dotEnv.path} (tentura-3zd)',
  );
  expect(
    dotEnvBytesAfterKill,
    bytesBefore,
    reason: 'workspace .env bytes must be unchanged after SIGKILL mid-harness',
  );
}

Future<ProcessResult> runWorkspaceFreshCheckoutHarnessProbe({
  required String serverPackageRoot,
  required String workspaceRepoRoot,
  required String probeTestRelative,
  required String probePlainName,
}) async {
  final repoRoot = p.normalize(p.join(serverPackageRoot, '../..'));
  final wrapper = p.join(repoRoot, 'scripts/run_with_test_cleanup.sh');
  return Process.run(
    wrapper,
    [
      '--timeout',
      '2m',
      '--',
      'bash',
      '-lc',
      'cd "$serverPackageRoot" && '
          'TENTURA_3ZD_WORKSPACE_PROBE=1 '
          'dart test test/support/hasura_pg_jwt_keys_test.dart '
          '--plain-name "$probePlainName"',
    ],
    workingDirectory: repoRoot,
  );
}
