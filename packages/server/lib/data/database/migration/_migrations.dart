import 'dart:math';

import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:postgres/postgres.dart';
import 'package:migrant_db_postgresql/migrant_db_postgresql.dart';

part 'm0193.dart';
part 'm0194.dart';
part 'm0195.dart';

/// `m0193` is a squashed baseline, not an ordinary migration: it is a generated
/// `pg_dump` of the schema that `m0001`…`m0192` (plus the out-of-band `0161a`
/// and `0163a`) used to build, verified character-identical to it. Regenerate
/// it with `tool/squash_baseline.dart`; never hand-edit it.
///
/// migrant applies `getInitial` only to a database with no `schema_version`
/// rows, and otherwise takes the first version sorting after
/// `MAX(schema_version.version)`. So a database at or past `0193` skips the
/// baseline entirely — but one *below* it would be handed the baseline and
/// would create objects over live ones. Check `MAX(version)` before deploying a
/// squash; see `docs/plans/migration-squash-plan.md`.
///
/// New migrations append here in increasing version order. That order is
/// load-bearing and `migration_registry_test.dart` guards it.
///
/// **Never edit a migration that has shipped, and never reuse a version
/// number.** migrant records a version once and never revisits it, so an
/// in-place edit reaches only the databases that had not yet reached that
/// version — the others keep the old schema silently and forever. Every drift
/// item found in the 2026-09-20 audit came from exactly this: `m0007` gained a
/// statement after it shipped, `m0133` gained a `DROP`, and version `0123` was
/// repurposed for an unrelated migration. See
/// `docs/plans/migration-squash-plan.md` §10. Correct a shipped migration by
/// adding a new one that asserts the intended state, the way `m0194` does.
final _allMigrations = <Migration>[m0193, m0194, m0195];

/// Test inventory in the exact order passed to migrant.
List<Migration> get migrationsForTesting => List.unmodifiable(_allMigrations);

const _schemaUpgradeLockKey = 'tentura_schema_upgrade';
final _upgradeBackoff = Random();

/// Migrant's gateway uses `LOCK TABLE … NOWAIT` and a try-advisory lock, so
/// parallel disposable-database upgrades throw [RaceCondition]. Serialize
/// with a blocking lock and retry the leftover races.
Future<void> _upgradeLocked(
  Connection connection,
  List<Migration> migrations,
) async {
  await connection.execute(
    Sql.named('SELECT pg_advisory_lock(hashtext(@key))'),
    parameters: {'key': _schemaUpgradeLockKey},
  );
  try {
    RaceCondition? last;
    for (var attempt = 0; attempt < 40; attempt++) {
      try {
        await Database(
          PostgreSQLGateway(connection),
        ).upgrade(InMemory(migrations));
        return;
      } on RaceCondition catch (error) {
        last = error;
        await Future<void>.delayed(
          Duration(milliseconds: 40 + attempt * 25 + _upgradeBackoff.nextInt(40)),
        );
      }
    }
    throw StateError(
      'schema upgrade raced after retries (${last?.message})',
    );
  } finally {
    await connection.execute(
      Sql.named('SELECT pg_advisory_unlock(hashtext(@key))'),
      parameters: {'key': _schemaUpgradeLockKey},
    );
  }
}

Future<void> migrateDbSchema(Connection connection) =>
    _upgradeLocked(connection, _allMigrations);

/// Applies an explicit migration list (truncated/legacy registries in tests).
Future<void> migrateDbSchemaFrom(
  Connection connection,
  List<Migration> migrations,
) => _upgradeLocked(connection, migrations);

/// Test helper: apply migrations through [lastInclusiveVersion] only.
Future<void> migrateDbSchemaThrough(
  Connection connection,
  String lastInclusiveVersion,
) {
  final selected = <Migration>[];
  for (final migration in _allMigrations) {
    selected.add(migration);
    if (migration.version == lastInclusiveVersion) {
      break;
    }
  }
  if (selected.isEmpty || selected.last.version != lastInclusiveVersion) {
    throw ArgumentError.value(
      lastInclusiveVersion,
      'lastInclusiveVersion',
      'unknown migration version',
    );
  }
  return _upgradeLocked(connection, selected);
}
