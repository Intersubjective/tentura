import 'dart:io';

/// Naive acceptance grep from repo root (all file types under lib).
const trustRebuildEffectiveLibGrepNeedle = 'trust_rebuild_effective';

const trustRebuildEffectiveServerLibGrepPath = 'packages/server/lib';

/// Shipped migration directory segment as reported by repo-root grep.
const trustRebuildEffectiveShippedMigrationPathSegment =
    'packages/server/lib/data/database/migration/';

const trustRebuildEffectiveM0193RepoPath =
    'packages/server/lib/data/database/migration/m0193.dart';

/// Env var the guard script must honor to grep a fixture repo root.
const trustRebuildEffectiveLibGrepRepoRootEnv =
    'TENTURA_TRUST_REBUILD_EFFECTIVE_GREP_REPO_ROOT';

class TrustRebuildEffectiveLibGrepHit {
  const TrustRebuildEffectiveLibGrepHit({
    required this.path,
    required this.line,
  });

  final String path;
  final int line;
}

bool trustRebuildEffectivePathIsShippedMigration(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.contains(trustRebuildEffectiveShippedMigrationPathSegment);
}

List<TrustRebuildEffectiveLibGrepHit> parseTrustRebuildEffectiveLibGrepOutput(
  String stdout,
) {
  final hits = <TrustRebuildEffectiveLibGrepHit>[];
  for (final raw in stdout.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final path = line.substring(0, colon);
    final rest = line.substring(colon + 1);
    final lineNum = int.tryParse(rest.split(':').first);
    if (lineNum == null) continue;
    hits.add(TrustRebuildEffectiveLibGrepHit(path: path, line: lineNum));
  }
  hits.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return hits;
}

ProcessResult runNaiveTrustRebuildEffectiveLibGrep({
  required String repoRoot,
}) {
  return Process.runSync(
    'grep',
    [
      '-rn',
      trustRebuildEffectiveLibGrepNeedle,
      trustRebuildEffectiveServerLibGrepPath,
    ],
    workingDirectory: repoRoot,
  );
}

List<TrustRebuildEffectiveLibGrepHit> naiveTrustRebuildEffectiveLibGrepHits({
  required String repoRoot,
}) {
  final result = runNaiveTrustRebuildEffectiveLibGrep(repoRoot: repoRoot);
  if (result.exitCode == 1 && result.stdout.toString().trim().isEmpty) {
    return [];
  }
  if (result.exitCode != 0 && result.exitCode != 1) {
    throw StateError(
      'grep failed (exit ${result.exitCode}): ${result.stderr}',
    );
  }
  return parseTrustRebuildEffectiveLibGrepOutput(result.stdout.toString());
}

/// Guard contract: non-empty list means the check must fail (exit 1).
List<TrustRebuildEffectiveLibGrepHit>
    trustRebuildEffectiveLibGuardOffendersFromHits(
  List<TrustRebuildEffectiveLibGrepHit> hits,
) {
  return hits
      .where((h) => !trustRebuildEffectivePathIsShippedMigration(h.path))
      .toList();
}

int trustRebuildEffectiveLibGuardExitCodeFromHits(
  List<TrustRebuildEffectiveLibGrepHit> hits,
) {
  return trustRebuildEffectiveLibGuardOffendersFromHits(hits).isEmpty ? 0 : 1;
}

File trustRebuildEffectiveLibGuardScriptFile(String repoRoot) {
  return File('$repoRoot/scripts/check-trust-rebuild-effective-lib.sh');
}

String trustRebuildEffectiveLibGrepFixtureRoot(String fixtureName) {
  return Directory(
    'test/fixtures/trust_rebuild_effective_lib_grep/$fixtureName',
  ).absolute.path;
}

ProcessResult runTrustRebuildEffectiveLibGuardScript({
  required String repoRoot,
  String? grepRepoRootOverride,
}) {
  final script = trustRebuildEffectiveLibGuardScriptFile(repoRoot);
  final environment = <String, String>{};
  if (grepRepoRootOverride != null) {
    environment[trustRebuildEffectiveLibGrepRepoRootEnv] = grepRepoRootOverride;
  }
  return Process.runSync(
    'bash',
    [script.path],
    workingDirectory: repoRoot,
    environment: environment.isEmpty ? null : environment,
  );
}

const _episodeClosureA5Start = '### A5 —';
const _episodeClosureA6Start = '### A6 —';

/// A5 unit block in episode-closure-implementation-steps.md (exclusive of A6).
String episodeClosureImplementationStepsA5Section(String stepsMarkdown) {
  final start = stepsMarkdown.indexOf(_episodeClosureA5Start);
  if (start < 0) {
    throw StateError('missing $_episodeClosureA5Start in steps doc');
  }
  final end = stepsMarkdown.indexOf(_episodeClosureA6Start, start);
  if (end < 0) {
    throw StateError('missing $_episodeClosureA6Start after A5');
  }
  return stepsMarkdown.substring(start, end);
}
