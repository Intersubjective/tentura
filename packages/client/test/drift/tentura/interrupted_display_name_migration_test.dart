import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/home/data/repository/home_orientation_preferences_repository.dart';

import 'generated/schema.dart';
import 'generated/schema_v3.dart' as v3;

const _accountId = 'U563b1646f6ff';
const _userId = 'Uec81add732dc';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'an interrupted display-name rename finishes and keeps the saved account',
    () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final schema = await verifier.schemaAt(3);
      addTearDown(schema.close);

      final oldDb = v3.DatabaseAtV3(schema.newConnection());
      await oldDb
          .into(oldDb.accounts)
          .insert(
            v3.AccountsCompanion.insert(
              id: _accountId,
              title: const Value('Alice'),
            ),
          );
      await oldDb
          .into(oldDb.friends)
          .insert(
            v3.FriendsCompanion.insert(
              subjectId: _accountId,
              objectId: 'Ufriend',
              title: const Value('Bob'),
            ),
          );
      await oldDb
          .into(oldDb.settings)
          .insert(
            v3.SettingsCompanion.insert(
              key: 'home:activated:$_userId',
              valueBool: const Value(0),
            ),
          );
      // Crash after the first statement of the title → display_name step.
      // user_version is still 3; friends.title is still the old column.
      await oldDb.customStatement(
        'ALTER TABLE accounts RENAME COLUMN title TO display_name',
      );
      await oldDb.close();

      final database = Database(
        const Env(),
        Logger('test'),
        schema.newConnection(),
      );
      addTearDown(database.close);
      final auth = AuthLocalRepository(
        Logger('test'),
        database,
        LocalSecureStorage(),
      );
      final home = HomeOrientationPreferencesRepository(database);

      final accounts = await auth.getAccountsAll();
      expect(
        [for (final account in accounts) account.displayName],
        ['Alice'],
      );

      await auth.updateAccount(
        const AccountEntity(id: _accountId, displayName: 'Alice'),
      );
      expect(
        [
          for (final account in await auth.getAccountsAll())
            account.displayName,
        ],
        ['Alice'],
      );

      final friend = await database.select(database.friends).getSingle();
      expect(friend.displayName, 'Bob');

      await home.setActivated(userId: _userId);
      expect(await home.isActivated(userId: _userId), isTrue);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data.values.single, 5);
      final contacts = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'contacts'",
          )
          .get();
      expect(contacts, isNotEmpty);
    },
  );
}
