@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/polling_act_repository.dart';
import 'package:tentura_server/env.dart';

/// Postgres integration — guards the m0104 re-key of `polling_act`.
///
/// Range voting upserts one row per variant with `insertOnConflictUpdate`,
/// which emits `ON CONFLICT (author_id, polling_variant_id)`. With m0004's
/// original PK of (author_id, polling_id) that conflict target has no matching
/// unique constraint and PostgreSQL raises 42P10; multi-variant votes also
/// collide on the old PK (23505). After m0104 both must succeed.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasVariantScopedPollingActPk(probe)) {
        skipReason = 'm0104 schema (polling_act re-key) missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late PollingActRepository repo;

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = PollingActRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.polling_act WHERE polling_id = 'Prangeupsert'",
      );
      await db.customStatement(
        "DELETE FROM public.polling_variant WHERE polling_id = 'Prangeupsert'",
      );
      await db.customStatement(
        "DELETE FROM public.polling WHERE id = 'Prangeupsert'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Urangeupsert%' ''',
      );
    });
  }

  Future<void> seedFixture() async {
    final key = '${'r' * 43}1';
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('Urangeupsertvoter', 'Voter', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO UPDATE SET public_key = EXCLUDED.public_key
''',
      [key],
    );
    await db.customStatement(
      '''
INSERT INTO public.polling (id, author_id, question, poll_type, is_anonymous, allow_revote, created_at, updated_at)
VALUES ('Prangeupsert', 'Urangeupsertvoter', 'Rate these', 'range', true, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
    await db.customStatement(
      '''
INSERT INTO public.polling_variant (id, polling_id, description)
VALUES
  ('PVrangeupsert1', 'Prangeupsert', 'Option A'),
  ('PVrangeupsert2', 'Prangeupsert', 'Option B')
ON CONFLICT (id) DO NOTHING
''',
    );
  }

  Future<int?> readScore(String variantId) async {
    final row = await db.customSelect(
      '''
SELECT score::int AS s
FROM public.polling_act
WHERE polling_id = 'Prangeupsert'
  AND author_id = 'Urangeupsertvoter'
  AND polling_variant_id = '$variantId'
''',
    ).getSingleOrNull();
    return row?.read<int?>('s');
  }

  test(
    'range vote upserts one row per variant and revote updates score',
    () async {
      await seedFixture();

      // First vote on two variants — must not raise 42P10 / 23505.
      await repo.upsert(
        authorId: 'Urangeupsertvoter',
        pollingId: 'Prangeupsert',
        variantIds: const ['PVrangeupsert1', 'PVrangeupsert2'],
        pollType: 'range',
        allowRevote: true,
        score: 3,
      );

      expect(await readScore('PVrangeupsert1'), 3);
      expect(await readScore('PVrangeupsert2'), 3);

      // Revote on one variant — insertOnConflictUpdate must update in place.
      await repo.upsert(
        authorId: 'Urangeupsertvoter',
        pollingId: 'Prangeupsert',
        variantIds: const ['PVrangeupsert1'],
        pollType: 'range',
        allowRevote: true,
        score: 5,
      );

      expect(await readScore('PVrangeupsert1'), 5);
      expect(await readScore('PVrangeupsert2'), 3);

      final rowCount = await db.customSelect(
        '''
SELECT COUNT(*)::int AS c
FROM public.polling_act
WHERE polling_id = 'Prangeupsert' AND author_id = 'Urangeupsertvoter'
''',
      ).getSingle();
      expect(rowCount.read<int>('c'), 2);
    },
    skip: skipReason,
  );
}

Env _testEnv() => Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );

/// True when `polling_act`'s primary key is keyed on
/// (author_id, polling_variant_id) — i.e. m0104 has been applied.
Future<bool> _hasVariantScopedPollingActPk(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.key_column_usage
WHERE table_schema = 'public'
  AND constraint_name = 'polling_act__pkey'
  AND column_name = 'polling_variant_id'
LIMIT 1
''',
  ).get();
  return rows.isNotEmpty;
}

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } on Object {
    return false;
  }
}
