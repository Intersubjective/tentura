@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

final _createsExtension = RegExp(
  r'CREATE\s+EXTENSION\s+IF\s+NOT\s+EXISTS\s+pg_stat_statements',
  caseSensitive: false,
);

const _extensionQuery =
    "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'";

Future<void> main() async {
  final creatorIndexes = [
    for (var i = 0; i < migrationsForTesting.length; i++)
      if (migrationsForTesting[i].statements.any(_createsExtension.hasMatch)) i,
  ];

  test(
    'exactly one registered migration creates pg_stat_statements with '
    'IF NOT EXISTS',
    () => expect(creatorIndexes, hasLength(1)),
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PG_STAT_STATEMENTS_EXTENSION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_pg_stat_statements',
  );
  final skipReason = await pgSkipReason(target);

  group('pg_stat_statements extension after schema migration', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      // `lastInclusiveVersion: null` means "clone the head template", so the
      // partial stop below needs a migration before the creator to stop at.
      final creator = creatorIndexes.isEmpty ? null : creatorIndexes.first;
      if (creator == null || creator == 0) {
        throw StateError(
          'pg_stat_statements must be created by a registered migration that '
          'is not the first one, so the schema can stop one migration short '
          'of it (creator index: $creator)',
        );
      }
      // Stop one migration short of the creator, so the test can prove the
      // extension appears only once that migration has run.
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: migrationsForTesting[creator - 1].version,
      );
      writer = session.writer;
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('is absent before the creating migration and present after '
        'migrateDbSchema', () async {
      expect(await writer.execute(_extensionQuery), isEmpty);

      await migrateDbSchema(writer);

      expect(await writer.execute(_extensionQuery), hasLength(1));
    });

    test('re-running the creating statements leaves one extension and '
        'raises no error', () async {
      await migrateDbSchema(writer);
      expect(creatorIndexes, isNotEmpty);

      for (final statement
          in migrationsForTesting[creatorIndexes.first].statements) {
        await writer.execute(statement);
      }

      expect(await writer.execute(_extensionQuery), hasLength(1));
    });
  }, skip: skipReason);
}
