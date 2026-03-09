import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/enum.dart';
import 'package:tentura/env.dart';

import 'database.steps.dart';
import 'tables/_tables.dart';

export 'package:drift/drift.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Friends,
    P2pMessages,
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
  int get schemaVersion => 3;

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
        await m.createTable(schema.p2pMessages);
        await m.createIndex(schema.p2pMessagesSender);
        await m.createIndex(schema.p2pMessagesReceiver);
        await m.createIndex(schema.p2pMessagesCreatedAt);
        await m.createIndex(schema.p2pMessagesDeliveredAt);
        await m.addColumn(schema.accounts, schema.accounts.fcmTokenUpdatedAt);

        await customStatement('DROP TABLE IF EXISTS messages;');
        await m.dropColumn(schema.accounts, 'has_avatar');
        await m.dropColumn(schema.friends, 'has_avatar');
      },
    ),
  );

  @disposeMethod
  Future<void> dispose() => super.close();
}
