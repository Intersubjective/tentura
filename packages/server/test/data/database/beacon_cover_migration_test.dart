@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0130 beacon cover migration', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'fresh schema gains cover columns, stage table, GC outbox, and constraints',
      () async {
        await migrateDbSchema(writer);

        final columns = await writer.execute(r'''
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'beacon'
  AND column_name IN ('primary_need_slug', 'cover_image_id', 'cover_source',
                      'icon_code', 'icon_background')
ORDER BY column_name
''');
        expect(
          columns.map((r) => r[0]).toList(),
          [
            'cover_image_id',
            'cover_source',
            'primary_need_slug',
          ],
        );
        final coverSource = columns.firstWhere((r) => r[0] == 'cover_source');
        expect(coverSource[2], 'NO');
        expect(coverSource[3]?.toString(), contains('0'));

        final tables = await writer.execute(r'''
SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('beacon_image_stage', 'image_object_gc')
ORDER BY tablename
''');
        expect(
          tables.map((r) => r[0]).toList(),
          ['beacon_image_stage', 'image_object_gc'],
        );

        final constraints = await writer.execute(r'''
SELECT conname FROM pg_constraint
WHERE conname IN (
  'beacon_cover_source_ck',
  'beacon_cover_image_membership_fk',
  'beacon_image_position_uq',
  'beacon_image_image_id_uq',
  'beacon_primary_need_membership_ck'
)
ORDER BY conname
''');
        expect(
          constraints.map((r) => r[0]).toList(),
          [
            'beacon_cover_image_membership_fk',
            'beacon_cover_source_ck',
            'beacon_image_image_id_uq',
            'beacon_image_position_uq',
            'beacon_primary_need_membership_ck',
          ],
        );

        final indexes = await writer.execute(r'''
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'beacon_cover_image_id_idx',
    'beacon_image_stage_expiry_idx',
    'image_object_gc_claim_idx'
  )
ORDER BY indexname
''');
        expect(
          indexes.map((r) => r[0]).toList(),
          [
            'beacon_cover_image_id_idx',
            'beacon_image_stage_expiry_idx',
            'image_object_gc_claim_idx',
          ],
        );
      },
      skip: skipReason,
    );

    test(
      'populated m0129 fixture backfills primary, cover, dense positions',
      () async {
        await _rollBackM0139ForTest(writer);
        await _rollBackM0138ForTest(writer);
        await _rollBackM0137ForTest(writer);
        await _rollBackM0136ForTest(writer);
        await _rollBackM0135ForTest(writer);
        await _rollBackM0134ForTest(writer);
        await _rollBackM0133ForTest(writer);
        await _rollBackM0132ForTest(writer);
        await _rollBackM0130ForTest(writer);

        await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Ucoverauthor', 'Cover author', 'cover-author-key'),
  ('Ucoverother', 'Other author', 'cover-other-key')
ON CONFLICT DO NOTHING
''');

        await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, needs)
VALUES
  ('Bcoverneeds', 'Ucoverauthor', 'Needs', 'd', 'other, transport, food'),
  ('Bcoverempty', 'Ucoverauthor', 'Empty', 'd', ''),
  ('Bcoverimgs', 'Ucoverauthor', 'Images', 'd', 'money')
ON CONFLICT DO NOTHING
''');

        final imageIds = await writer.execute(r'''
INSERT INTO public.image (id, author_id, height, width, hash)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Ucoverauthor', 1, 1, 'a'),
  ('22222222-2222-2222-2222-222222222222', 'Ucoverauthor', 1, 1, 'b'),
  ('33333333-3333-3333-3333-333333333333', 'Ucoverauthor', 1, 1, 'c')
ON CONFLICT DO NOTHING
RETURNING id::text
''');
        expect(imageIds.length, greaterThanOrEqualTo(0));

        await writer.execute(r'''
DELETE FROM public.beacon_image WHERE beacon_id = 'Bcoverimgs'
''');
        // Non-dense / out-of-order positions; densify by (position, image_id).
        await writer.execute(r'''
INSERT INTO public.beacon_image (beacon_id, image_id, position)
VALUES
  ('Bcoverimgs', '22222222-2222-2222-2222-222222222222', 5),
  ('Bcoverimgs', '11111111-1111-1111-1111-111111111111', 5),
  ('Bcoverimgs', '33333333-3333-3333-3333-333333333333', 9)
''');

        // Re-apply only m0130 via migrant (earlier versions already recorded).
        await migrateDbSchema(writer);

        final primary = await writer.execute(r'''
SELECT primary_need_slug FROM public.beacon WHERE id = 'Bcoverneeds'
''');
        expect(primary.single.single, 'transport');

        final emptyPrimary = await writer.execute(r'''
SELECT primary_need_slug FROM public.beacon WHERE id = 'Bcoverempty'
''');
        expect(emptyPrimary.single.single, isNull);

        final positions = await writer.execute(r'''
SELECT image_id::text, position
FROM public.beacon_image
WHERE beacon_id = 'Bcoverimgs'
ORDER BY position, image_id
''');
        expect(
          positions.map((r) => [r[0], r[1]]).toList(),
          [
            ['11111111-1111-1111-1111-111111111111', 0],
            ['22222222-2222-2222-2222-222222222222', 1],
            ['33333333-3333-3333-3333-333333333333', 2],
          ],
        );

        final cover = await writer.execute(r'''
SELECT cover_image_id::text, cover_source
FROM public.beacon WHERE id = 'Bcoverimgs'
''');
        expect(cover.single[0], '11111111-1111-1111-1111-111111111111');
        expect(cover.single[1], 0);

        // Composite membership rejects cover outside attached set.
        await expectLater(
          writer.execute(r'''
UPDATE public.beacon
SET cover_image_id = '33333333-3333-3333-3333-333333333333'
WHERE id = 'Bcoverneeds'
'''),
          throwsA(isA<Exception>()),
        );

        // Targeted SET NULL when attachment deleted.
        await writer.execute(r'''
DELETE FROM public.beacon_image
WHERE beacon_id = 'Bcoverimgs'
  AND image_id = '11111111-1111-1111-1111-111111111111'
''');
        final afterDelete = await writer.execute(r'''
SELECT cover_image_id FROM public.beacon WHERE id = 'Bcoverimgs'
''');
        expect(afterDelete.single.single, isNull);

        // Deferrable full reorder inside one transaction.
        await writer.execute('BEGIN');
        await writer.execute(r'''
UPDATE public.beacon_image SET position = 10
WHERE beacon_id = 'Bcoverimgs'
  AND image_id = '22222222-2222-2222-2222-222222222222'
''');
        await writer.execute(r'''
UPDATE public.beacon_image SET position = 0
WHERE beacon_id = 'Bcoverimgs'
  AND image_id = '33333333-3333-3333-3333-333333333333'
''');
        await writer.execute(r'''
UPDATE public.beacon_image SET position = 1
WHERE beacon_id = 'Bcoverimgs'
  AND image_id = '22222222-2222-2222-2222-222222222222'
''');
        await writer.execute('COMMIT');

        final reordered = await writer.execute(r'''
SELECT image_id::text, position
FROM public.beacon_image
WHERE beacon_id = 'Bcoverimgs'
ORDER BY position
''');
        expect(
          reordered.map((r) => [r[0], r[1]]).toList(),
          [
            ['33333333-3333-3333-3333-333333333333', 0],
            ['22222222-2222-2222-2222-222222222222', 1],
          ],
        );

        // Unique image_id rejects attaching the same image to two beacons.
        await expectLater(
          writer.execute(r'''
INSERT INTO public.beacon_image (beacon_id, image_id, position)
VALUES ('Bcoverneeds', '22222222-2222-2222-2222-222222222222', 0)
'''),
          throwsA(isA<Exception>()),
        );

        await writer.execute(r'''
INSERT INTO public.beacon_image_stage (image_id, beacon_id)
VALUES ('11111111-1111-1111-1111-111111111111', 'Bcoverimgs')
''');
        await writer.execute(r'''
INSERT INTO public.image_object_gc (image_id, author_id)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Ucoverauthor')
''');
        final stageCount = await writer.execute(
          'SELECT count(*)::int FROM public.beacon_image_stage',
        );
        final gcCount = await writer.execute(
          'SELECT count(*)::int FROM public.image_object_gc',
        );
        expect(stageCount.single.single, 1);
        expect(gcCount.single.single, 1);
      },
      skip: skipReason,
    );
  });
}

Future<void> _rollBackM0139ForTest(Connection connection) async {
  for (final statement in const [
    'DROP TABLE IF EXISTS public.beacon_commitment_event',
    'ALTER TABLE public.beacon_help_offer '
        'DROP CONSTRAINT IF EXISTS beacon_help_offer_offer_kind_check',
    'ALTER TABLE public.beacon_help_offer '
        'DROP CONSTRAINT IF EXISTS beacon_help_offer_stake_state_check',
    'ALTER TABLE public.beacon_help_offer DROP COLUMN IF EXISTS offer_kind',
    'ALTER TABLE public.beacon_help_offer DROP COLUMN IF EXISTS stake_state',
    'ALTER TABLE public.beacon DROP COLUMN IF EXISTS review_reopen_count',
    "DELETE FROM public.schema_version WHERE version = '0139'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0138ForTest(Connection connection) async {
  for (final statement in const [
    r'''
ALTER TABLE public.user_block_intent
  DROP CONSTRAINT IF EXISTS user_block_intent_cascade_mode_check
''',
    r'''
ALTER TABLE public.user_block_intent
  ADD CONSTRAINT user_block_intent_cascade_mode_check
    CHECK (cascade_mode IN (0, 1, 2))
''',
    r'''
CREATE OR REPLACE FUNCTION public.block_cascade_candidates(
  _blocker text, _root text, _mode smallint, _max_depth integer, _limit integer
) RETURNS TABLE (user_id text, depth integer)
  LANGUAGE sql STABLE AS $$
WITH RECURSIVE sub AS (
  SELECT g.descendant_node_key AS k, g.descendant_user_id AS uid, 1 AS depth
  FROM public.invite_genealogy g
  WHERE g.ancestor_user_id = _root
  UNION ALL
  SELECT g.descendant_node_key, g.descendant_user_id, s.depth + 1
  FROM public.invite_genealogy g
  JOIN sub s ON g.ancestor_node_key = s.k
  WHERE s.depth < _max_depth
    AND s.uid IS DISTINCT FROM _blocker
    AND (s.uid IS NULL
         OR _mode = 2
         OR public.block_cascade_unattached(_blocker, _root, s.uid))
)
SELECT s.uid, min(s.depth)::int
FROM sub s
WHERE s.uid IS NOT NULL
  AND s.uid <> _blocker
  AND (_mode = 2 OR public.block_cascade_unattached(_blocker, _root, s.uid))
GROUP BY s.uid
ORDER BY 2, 1
LIMIT _limit;
$$;
''',
    "DELETE FROM public.schema_version WHERE version = '0138'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0137ForTest(Connection connection) async {
  await connection.execute(
    "DELETE FROM public.schema_version WHERE version = '0137'",
  );
}

Future<void> _rollBackM0136ForTest(Connection connection) async {
  for (final statement in const [
    'DROP TRIGGER IF EXISTS user_block_inherit_trg ON public.invite_genealogy',
    'DROP FUNCTION IF EXISTS public.user_block_inherit_on_invite()',
    'DROP FUNCTION IF EXISTS public.graph_edges_between(text[], boolean, json)',
    "DELETE FROM public.schema_version WHERE version = '0136'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0135ForTest(Connection connection) async {
  for (final statement in const [
    'DROP TABLE IF EXISTS public.user_block_intent',
    'DROP TABLE IF EXISTS public.user_block',
    'DROP FUNCTION IF EXISTS public.block_cascade_candidates(text, text, smallint, integer, integer)',
    'DROP FUNCTION IF EXISTS public.block_cascade_unattached(text, text, text)',
    'DROP FUNCTION IF EXISTS public.block_hides(text, text)',
    "DELETE FROM public.schema_version WHERE version = '0135'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0134ForTest(Connection connection) async {
  for (final statement in const [
    'DROP FUNCTION IF EXISTS public.graph_edges_between(text[], boolean)',
    "DELETE FROM public.schema_version WHERE version = '0134'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0133ForTest(Connection connection) async {
  for (final statement in const [
    'DROP TRIGGER IF EXISTS beacon_room_message_attachment_notify '
        'ON public.beacon_room_message_attachment',
    'DROP FUNCTION IF EXISTS public.notify_room_message_attachment_change()',
    'DROP FUNCTION IF EXISTS public.emit_realtime_entity_change(text, text, text, text[], jsonb)',
    "DELETE FROM public.schema_version WHERE version = '0133'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0132ForTest(Connection connection) async {
  for (final statement in const [
    'ALTER TABLE public.beacon DROP COLUMN IF EXISTS cover_thumb_image_id',
    "DELETE FROM public.schema_version WHERE version = '0132'",
  ]) {
    await connection.execute(statement);
  }
}

Future<void> _rollBackM0130ForTest(Connection connection) async {
  for (final statement in const [
    // m0131 sits above m0130, and migrant only applies versions above the
    // highest recorded one. Leaving '0131' recorded would make the
    // re-application of m0130 below a silent no-op, so unwind it first.
    '''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_primary_need_membership_ck
''',
    'ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS icon_code TEXT NULL',
    '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS icon_background INTEGER NULL
''',
    "DELETE FROM public.schema_version WHERE version = '0131'",
    'ALTER TABLE public.beacon DROP CONSTRAINT IF EXISTS beacon_cover_image_membership_fk',
    'DROP INDEX IF EXISTS public.beacon_cover_image_id_idx',
    'DROP TABLE IF EXISTS public.beacon_image_stage',
    'DROP TABLE IF EXISTS public.image_object_gc',
    'ALTER TABLE public.beacon_image DROP CONSTRAINT IF EXISTS beacon_image_position_uq',
    'ALTER TABLE public.beacon_image DROP CONSTRAINT IF EXISTS beacon_image_image_id_uq',
    'ALTER TABLE public.beacon DROP CONSTRAINT IF EXISTS beacon_cover_source_ck',
    '''
ALTER TABLE public.beacon
  DROP COLUMN IF EXISTS primary_need_slug,
  DROP COLUMN IF EXISTS cover_image_id,
  DROP COLUMN IF EXISTS cover_source
''',
    "DELETE FROM public.schema_version WHERE version = '0130'",
  ]) {
    await connection.execute(statement);
  }
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_BEACON_COVER_MIGRATION_TEST_DB'] ??
        'tentura_test_bcover_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_BEACON_COVER_MIGRATION_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
