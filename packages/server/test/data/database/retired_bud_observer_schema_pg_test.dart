@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

const _lastShippedVersion = '0319';
const _migrationDir = 'lib/data/database/migration';
const _observerTable = 'beacon_bud_observer';
// Digest of sorted migration paths and source through m0319 at 3a159c1d6.
const _shippedMigrationDigest =
    '58d713d925217a1f5e37b8ea066ad0ac1351836ecdd59f9ebe4414a91e72b25c';

final _migrationPath = RegExp('^$_migrationDir/m([0-9]{4})[.]dart\$');
final _dropObserverTable = RegExp(
  r'^\s*DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:"?public"?\.)?'
  '"?$_observerTable"?(?=\\s|;|\$)',
  caseSensitive: false,
  multiLine: true,
);

// These files only reference the former table to replay pre-drop policy.
const _historicalTestFiles = {
  'test/data/database/m0239_post_bud_schema_pg_test.dart',
  'test/data/database/fixtures/questions_shipped_migrations.json',
  'test/data/repository/post_bud_hierarchy_realtime_pg_test.dart',
  'test/data/repository/post_bud_read_wall_pg_test.dart',
  'test/domain/use_case/beacon_questions_audience_visibility_cost_pg_test.dart',
};
const _retirementTest =
    'test/data/database/retired_bud_observer_schema_pg_test.dart';

Iterable<File> _filesIn(String directory) =>
    Directory(directory).listSync(recursive: true).whereType<File>();

bool _mentionsObserverTable(File file) => utf8
    .decode(file.readAsBytesSync(), allowMalformed: true)
    .contains(_observerTable);

final _dropMigrations = migrationsForTesting.where(
  (migration) =>
      migration.version.compareTo(_lastShippedVersion) > 0 &&
      migration.statements.any(_dropObserverTable.hasMatch),
);

Future<void> main() async {
  test(
    'a new registered migration retires Post observers and preserves shipped history',
    () {
      final shippedPaths = [
        for (final file in _filesIn(_migrationDir))
          if (_migrationPath.firstMatch(file.path) case final match?)
            if (match[1]!.compareTo(_lastShippedVersion) <= 0) file.path,
      ]..sort();
      expect(
        migrationsForTesting
            .takeWhile(
              (migration) =>
                  migration.version.compareTo(_lastShippedVersion) <= 0,
            )
            .map((migration) => '$_migrationDir/m${migration.version}.dart'),
        orderedEquals(shippedPaths),
      );
      final shippedSources = shippedPaths
          .map((path) => '$path\n${File(path).readAsStringSync()}')
          .join('\u0000');
      expect(
        sha256.convert(utf8.encode(shippedSources)).toString(),
        _shippedMigrationDigest,
      );
      expect(
        _dropMigrations.map((migration) => migration.version),
        hasLength(1),
      );
    },
  );

  test(
    'server source and live tests have no references to retired Post observers',
    () {
      final migrationPaths = {
        for (final migration in migrationsForTesting)
          if (migration.version.compareTo(_lastShippedVersion) <= 0)
            '$_migrationDir/m${migration.version}.dart',
        for (final migration in _dropMigrations)
          '$_migrationDir/m${migration.version}.dart',
      };
      final sourceReferences = [
        for (final file in _filesIn('lib'))
          if (!migrationPaths.contains(file.path) &&
              _mentionsObserverTable(file))
            file.path,
      ]..sort();
      final testReferences = [
        for (final file in _filesIn('test'))
          if (file.path != _retirementTest &&
              !_historicalTestFiles.contains(file.path) &&
              _mentionsObserverTable(file))
            file.path,
      ]..sort();
      expect(
        {'source': sourceReferences, 'tests': testReferences},
        {
          'source': isEmpty,
          'tests': isEmpty,
        },
      );
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_RETIRED_BUD_OBSERVER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_retired_bud_observer',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrading an existing Request database', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: _lastShippedVersion,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await migrateDbSchema(session.writer);
    });

    test('removes the former Post observer table and its indexes', () async {
      final rows = await session.writer.execute('''
SELECT to_regclass('public.beacon_bud_observer')::text,
       ARRAY(SELECT indexname::text FROM pg_indexes
             WHERE schemaname = 'public' AND indexname IN (
               'beacon_bud_observer_pkey', 'beacon_bud_observer_user_idx'
             ) ORDER BY indexname)
''');
      expect(rows.single.toList(), [null, isEmpty]);
    });

    test(
      'leaves no public function depending on Post observer grants',
      () async {
        final rows = await session.writer.execute('''
SELECT p.proname::text FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosrc LIKE '%beacon_bud_observer%'
ORDER BY p.proname
''');
        expect([for (final row in rows) row.single], isEmpty);
      },
    );
  });
}
