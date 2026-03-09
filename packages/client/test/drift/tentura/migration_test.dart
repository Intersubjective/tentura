// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:tentura/data/database/database.dart';
import 'package:tentura/env.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = _openTestDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  // The following template shows how to write tests ensuring your migrations
  // preserve existing data.
  // Testing this can be useful for migrations that change existing columns
  // (e.g. by alterating their type or constraints). Migrations that only add
  // tables or columns typically don't need these advanced tests. For more
  // information, see https://drift.simonbinder.eu/migrations/tests/#verifying-data-integrity
  // TODO: This generated template shows how these tests could be written. Adopt
  // it to your own needs when testing migrations with data integrity.
  test('migration from v1 to v2 does not corrupt data', () async {
    // Add data to insert into the old database, and the expected rows after the
    // migration.
    // TODO: Fill these lists
    final oldMessagesData = <v1.MessagesData>[];
    final expectedNewMessagesData = <v2.MessagesData>[];

    final oldSettingsData = <v1.SettingsData>[];
    final expectedNewSettingsData = <v2.SettingsData>[];

    final oldFriendsData = <v1.FriendsData>[];
    final expectedNewFriendsData = <v2.FriendsData>[];

    final oldAccountsData = <v1.AccountsData>[];
    final expectedNewAccountsData = <v2.AccountsData>[];

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: _openTestDatabase,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.messages, oldMessagesData);
        batch.insertAll(oldDb.settings, oldSettingsData);
        batch.insertAll(oldDb.friends, oldFriendsData);
        batch.insertAll(oldDb.accounts, oldAccountsData);
      },
      validateItems: (newDb) async {
        expect(
            expectedNewMessagesData, await newDb.select(newDb.messages).get());
        expect(
            expectedNewSettingsData, await newDb.select(newDb.settings).get());
        expect(expectedNewFriendsData, await newDb.select(newDb.friends).get());
        expect(
            expectedNewAccountsData, await newDb.select(newDb.accounts).get());
      },
    );
  });
}

Database _openTestDatabase(QueryExecutor executor) =>
    Database(const Env(), Logger(level: Level.nothing), executor);
