// tentura-2vzj (tentura-0cl.2.8): migration-aware guard replaces naive zero-match
// `grep -rn trust_rebuild_effective packages/server/lib`.

import 'dart:io';

import 'package:test/test.dart';

import '../support/trust_rebuild_effective_lib_grep.dart';

Directory _repoRoot() => Directory('../..').absolute;

File _repoFile(String relativePath) =>
    File('${_repoRoot().path}/$relativePath');

final _zeroMatchNaiveGrepAcceptance = RegExp(
  r'grep\s+-rn\s+.*trust_rebuild_effective.*packages/server/lib'
  r'[^\n]*\breturns\s+nothing\b',
  caseSensitive: false,
);

void main() {
  group('tentura-2vzj trust_rebuild_effective lib grep acceptance', () {
    late File script;

    setUp(() {
      script = trustRebuildEffectiveLibGuardScriptFile(_repoRoot().path);
    });

    test(
      'scripts/check-trust-rebuild-effective-lib.sh exists, is executable, '
      'and encodes repo-root grep plus migration allowlist',
      () {
        expect(
          script.existsSync(),
          isTrue,
          reason:
              'add ${script.path} — naive lib grep cannot be zero-match while '
              'shipped migrations on main still define trust_rebuild_effective_*',
        );
        expect(
          script.statSync().modeString(),
          contains('x'),
          reason: 'trust_rebuild_effective lib guard must be executable',
        );
        final source = script.readAsStringSync();
        expect(
          source,
          contains('grep -rn'),
          reason: 'guard must run the same naive grep Alloy documents',
        );
        expect(source, contains(trustRebuildEffectiveLibGrepNeedle));
        expect(source, contains(trustRebuildEffectiveServerLibGrepPath));
        expect(
          source,
          contains(trustRebuildEffectiveShippedMigrationPathSegment),
          reason: 'guard must allow only shipped migration paths',
        );
        expect(
          source,
          contains(trustRebuildEffectiveLibGrepRepoRootEnv),
          reason: 'guard must support fixture roots for contract tests',
        );
      },
    );

    test(
      'm0193.dart on main is pinned and not edited locally vs main',
      () {
        final log = Process.runSync(
          'git',
          [
            'log',
            'main',
            '-1',
            '--format=%H',
            '--',
            trustRebuildEffectiveM0193RepoPath,
          ],
          workingDirectory: _repoRoot().path,
        );
        expect(log.exitCode, 0, reason: 'stderr: ${log.stderr}');
        expect(
          log.stdout.toString().trim(),
          trustRebuildEffectiveM0193MainHeadPin,
          reason: 'shipped m0193 commit on main',
        );

        final diff = Process.runSync(
          'git',
          ['diff', 'main', '--', trustRebuildEffectiveM0193RepoPath],
          workingDirectory: _repoRoot().path,
        );
        expect(diff.exitCode, 0);
        expect(
          diff.stdout.toString(),
          isEmpty,
          reason: 'do not edit shipped m0193 locally; use new migrations',
        );

        final show = Process.runSync(
          'git',
          ['show', 'main:$trustRebuildEffectiveM0193RepoPath'],
          workingDirectory: _repoRoot().path,
        );
        expect(show.exitCode, 0);
        expect(
          show.stdout,
          contains('CREATE FUNCTION public.trust_rebuild_effective_edge'),
        );
      },
    );

    test(
      'A5 section specifies migration-aware guard verify, not zero-match naive grep',
      () {
        final steps = _repoFile(
          'docs/plans/episode-closure-implementation-steps.md',
        ).readAsStringSync();
        final a5 = episodeClosureImplementationStepsA5Section(steps);
        expect(
          _zeroMatchNaiveGrepAcceptance.hasMatch(a5),
          isFalse,
          reason:
              'A5 must not require zero-match naive grep while migrations on '
              'main stay immutable',
        );
        expect(
          a5,
          isNot(
            contains(
              'grep -rn "trust_rebuild_effective" packages/server/lib` '
              'returns nothing',
            ),
          ),
        );
        expect(
          a5,
          contains('scripts/check-trust-rebuild-effective-lib.sh'),
          reason: 'A5 verify must name the migration-aware guard script',
        );
        final verifyLines = a5
            .split('\n')
            .where(
              (line) =>
                  line.contains('trust_rebuild_effective') &&
                  line.contains('packages/server/lib'),
            )
            .toList();
        for (final line in verifyLines) {
          expect(
            line,
            anyOf(
              contains('check-trust-rebuild-effective-lib'),
              contains('data/database/migration'),
              contains('shipped migration'),
              contains('immutable migration'),
            ),
            reason: 'A5 line still uses naive grep without migration allowlist: '
                '$line',
          );
        }
      },
    );
  });
}
