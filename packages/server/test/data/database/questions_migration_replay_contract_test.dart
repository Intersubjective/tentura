@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

const _migrationDir = 'lib/data/database/migration';
const _fixtures = 'test/data/database/fixtures';

void main() {
  test('fresh upgrades include a frozen Questions policy after version 0308', () {
    final upgrades = migrationsForTesting
        .where(
          (migration) =>
              migration.version.compareTo('0308') > 0 &&
              migration.statements.any(
                (sql) => RegExp(
                  r'CREATE OR REPLACE FUNCTION public\.questions_access_levels\s*\(',
                ).hasMatch(sql),
              ),
        )
        .toList();
    expect(
      upgrades,
      isNotEmpty,
      reason: 'already upgraded databases need a registered policy migration',
    );
    for (final migration in upgrades) {
      final source = File(
        '$_migrationDir/m${migration.version}.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(contains(r'${')),
        reason: 'replaying this migration must not depend on live Dart helpers',
      );
      final registry = File(
        '$_migrationDir/_migrations.dart',
      ).readAsStringSync();
      expect(registry, contains("part 'm${migration.version}.dart';"));
    }
  });

  test(
    'shipped Questions SQL replays byte for byte',
    () {
      // Captured by evaluating all three migrations and their SQL helpers from
      // commit 071519a2d, not by rendering the current working-tree helpers.
      final frozen =
          jsonDecode(
                File(
                  '$_fixtures/questions_shipped_migrations.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final version in ['0289', '0299', '0300']) {
        final migration = migrationsForTesting.singleWhere(
          (m) => m.version == version,
        );
        expect(
          migration.statements,
          frozen[version],
          reason:
              'a fresh database must replay the shipped $version statements exactly',
        );
      }
    },
  );
}
