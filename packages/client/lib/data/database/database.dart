import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';

import 'database.steps.dart';
import 'tables/_tables.dart';

export 'package:drift/drift.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Contacts,
    Friends,
    Settings,
  ],
)
@singleton
final class Database extends _$Database {
  Database(
    this._env,
    this._logger,
    super.e,
  );

  final Env _env;

  final Logger _logger;

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      _logger
        ..warning('Creating tables...')
        ..warning(allTables);
      await migrator.createAll();
    },
    beforeOpen: (details) async {
      if (_env.clearDatabase) {
        _logger.warning('Clearing database...');
        final m = Migrator(this);
        for (final entity in allSchemaEntities) {
          _logger.warning(entity.entityName);
          await m.drop(entity);
          await m.create(entity);
        }
      }
      await customStatement('PRAGMA foreign_keys = ON;');
    },
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        _logger.warning('Migrating step 1 to 2...');
        await m.addColumn(schema.accounts, schema.accounts.imageId);
        await m.addColumn(schema.accounts, schema.accounts.blurHash);
        await m.addColumn(schema.accounts, schema.accounts.height);
        await m.addColumn(schema.accounts, schema.accounts.width);

        await m.addColumn(schema.friends, schema.friends.imageId);
        await m.addColumn(schema.friends, schema.friends.blurHash);
        await m.addColumn(schema.friends, schema.friends.height);
        await m.addColumn(schema.friends, schema.friends.width);
      },
      from2To3: (m, schema) async {
        _logger.warning('Migrating step 2 to 3...');
        await m.addColumn(schema.accounts, schema.accounts.fcmTokenUpdatedAt);

        await customStatement('DROP TABLE IF EXISTS messages;');
        await m.dropColumn(schema.accounts, 'has_avatar');
        await m.dropColumn(schema.friends, 'has_avatar');
      },
      from3To4: (m, schema) async {
        _logger.warning('Migrating step 3 to 4 (title → display_name)...');
        // user_version moves only after this step returns, and each rename
        // commits on its own. A crash between them leaves the first column
        // renamed; the next open runs the step again (#853).
        await _renameColumnIfPresent('accounts', 'title', 'display_name');
        await _renameColumnIfPresent('friends', 'title', 'display_name');
      },
      from4To5: (m, schema) async {
        _logger.warning('Migrating step 4 to 5 (contacts)...');
        await m.createTable(schema.contacts);
      },
    ),
  );

  /// Renames [from] to [to] when [from] is still present.
  Future<void> _renameColumnIfPresent(
    String table,
    String from,
    String to,
  ) async {
    final columns = await customSelect('PRAGMA table_info($table)').get();
    final hasFrom = columns.any((row) => row.data['name'] == from);
    if (!hasFrom) {
      return;
    }
    await customStatement('ALTER TABLE $table RENAME COLUMN $from TO $to');
  }

  @disposeMethod
  Future<void> dispose() => super.close();
}
