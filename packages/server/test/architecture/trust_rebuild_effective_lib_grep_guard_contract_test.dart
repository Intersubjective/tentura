// Contract for migration-aware trust_rebuild_effective lib guard (tentura-2vzj).

import 'dart:io';

import 'package:test/test.dart';

import '../support/trust_rebuild_effective_lib_grep.dart';

Directory _repoRoot() => Directory('../..').absolute;

void main() {
  group('trust_rebuild_effective lib grep guard contract', () {
    late File script;

    setUp(() {
      script = trustRebuildEffectiveLibGuardScriptFile(_repoRoot().path);
    });

    test(
      'guard script exits 0 on current repo when naive grep hits are migration-only',
      () {
        expect(script.existsSync(), isTrue, reason: 'missing ${script.path}');
        final hits = naiveTrustRebuildEffectiveLibGrepHits(
          repoRoot: _repoRoot().path,
        );
        expect(
          hits,
          isNotEmpty,
          reason: 'm0193 on main must still mention rebuild SQL in migrations',
        );
        final expectedExit =
            trustRebuildEffectiveLibGuardExitCodeFromHits(hits);
        final result = runTrustRebuildEffectiveLibGuardScript(
          repoRoot: _repoRoot().path,
        );
        expect(
          result.exitCode,
          expectedExit,
          reason:
              'script must classify live grep the same as migration allowlist; '
              'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
        expect(expectedExit, 0, reason: 'live tree must have no caller hits');
      },
    );

    test(
      'guard script fails on offender fixture (non-migration grep hit)',
      () {
        expect(script.existsSync(), isTrue, reason: 'missing ${script.path}');
        final fixtureRoot =
            trustRebuildEffectiveLibGrepFixtureRoot('offender_tree');
        final hits = naiveTrustRebuildEffectiveLibGrepHits(
          repoRoot: fixtureRoot,
        );
        expect(
          trustRebuildEffectiveLibGuardExitCodeFromHits(hits),
          1,
          reason: 'fixture must include a non-migration grep hit',
        );
        final result = runTrustRebuildEffectiveLibGuardScript(
          repoRoot: _repoRoot().path,
          grepRepoRootOverride: fixtureRoot,
        );
        expect(
          result.exitCode,
          isNonZero,
          reason:
              'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      },
    );

    test(
      'guard script passes on migration-only fixture',
      () {
        expect(script.existsSync(), isTrue, reason: 'missing ${script.path}');
        final fixtureRoot =
            trustRebuildEffectiveLibGrepFixtureRoot('migration_only_tree');
        final hits = naiveTrustRebuildEffectiveLibGrepHits(
          repoRoot: fixtureRoot,
        );
        expect(hits, isNotEmpty);
        expect(trustRebuildEffectiveLibGuardExitCodeFromHits(hits), 0);
        final result = runTrustRebuildEffectiveLibGuardScript(
          repoRoot: _repoRoot().path,
          grepRepoRootOverride: fixtureRoot,
        );
        expect(
          result.exitCode,
          0,
          reason:
              'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        );
      },
    );

    test(
      'offender fixture includes a non-.dart match (grep scope, not dart-only scan)',
      () {
        final hits = naiveTrustRebuildEffectiveLibGrepHits(
          repoRoot: trustRebuildEffectiveLibGrepFixtureRoot('offender_tree'),
        );
        expect(
          hits.map((h) => h.path),
          anyElement(endsWith('.txt')),
        );
      },
    );
  });
}
