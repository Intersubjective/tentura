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

    test('shipped m0193.dart still defines trust_rebuild_effective_edge', () {
      expect(
        _repoFile(trustRebuildEffectiveM0193RepoPath).readAsStringSync(),
        contains('CREATE FUNCTION public.trust_rebuild_effective_edge'),
        reason: 'do not edit shipped m0193; use new migrations',
      );
    });

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
