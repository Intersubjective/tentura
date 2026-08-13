@Tags(['pg'])
library;

import 'dart:convert';
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

  group('m0148 user_availability migration', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
    });

    tearDown(() async {
      for (final statement in [
        'DELETE FROM public.user_block '
            "WHERE blocker_id LIKE 'Um0148%' OR blocked_id LIKE 'Um0148%'",
        'DELETE FROM public.user_availability WHERE user_id LIKE \'Um0148%\'',
        'DELETE FROM public."user" WHERE id LIKE \'Um0148%\'',
      ]) {
        try {
          await writer.execute(statement);
        } on Object {
          // First test runs before migrateDbSchema; tables may not exist yet.
        }
      }
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'disposable target uses an isolated database name',
      () {
        expect(target.databaseName, startsWith('tentura_test_'));
        expect(target.databaseName, isNot('postgres'));
        expect(target.databaseEnv.pgDatabase, target.databaseName);
      },
      skip: skipReason,
    );

    test(
      'fresh schema creates logged user_availability, CHECK, index, and hidden function',
      () async {
        await migrateDbSchema(writer);
        await _expectM0148Schema(writer);
      },
      skip: skipReason,
    );

    test(
      'CHECK rejects empty rows; FK cascades; no per-user backfill',
      () async {
        await migrateDbSchema(writer);

        await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Um0148open', 'Open', 'pk-open'),
  ('Um0148child', 'Child', 'pk-child')
ON CONFLICT DO NOTHING
''');

        final sparseCount = await writer.execute(
          'SELECT count(*)::int FROM public.user_availability',
        );
        expect(sparseCount.single.single, 0);

        await expectLater(
          writer.execute(r'''
INSERT INTO public.user_availability (user_id, is_limited, resume_on)
VALUES ('Um0148open', false, NULL)
'''),
          throwsA(isA<Exception>()),
        );

        await writer.execute(r'''
INSERT INTO public.user_availability (user_id, is_limited, resume_on)
VALUES ('Um0148open', true, NULL)
''');

        await writer.execute(r'''
INSERT INTO public.user_availability (user_id, is_limited, resume_on)
VALUES ('Um0148child', false, CURRENT_DATE + 7)
''');

        await writer.execute(
          '''DELETE FROM public."user" WHERE id = 'Um0148child' ''',
        );
        final childRow = await writer.execute(
          '''SELECT count(*)::int FROM public.user_availability '''
          '''WHERE user_id = 'Um0148child' ''',
        );
        expect(childRow.single.single, 0);
      },
      skip: skipReason,
    );

    test(
      'hidden_for_viewer delegates symmetric block_hides like user_presence',
      () async {
        await migrateDbSchema(writer);

        const viewerId = 'Um0148viewer';
        const peerId = 'Um0148peer';
        final session = _sessionJson(viewerId);

        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('$viewerId', 'Viewer', 'pk-viewer'),
  ('$peerId', 'Peer', 'pk-peer')
ON CONFLICT DO NOTHING
''');
        await writer.execute('''
INSERT INTO public.user_availability (user_id, is_limited)
VALUES ('$viewerId', true), ('$peerId', true)
ON CONFLICT DO NOTHING
''');

        final visibleBefore = await _queryVisibleAvailabilityUserIds(
          writer,
          session,
        );
        expect(visibleBefore, containsAll([viewerId, peerId]));

        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewerId', '$peerId', '$peerId')
ON CONFLICT DO NOTHING
''');

        final visibleAfterBlock = await _queryHiddenAvailabilityUserIds(
          writer,
          session,
        );
        expect(visibleAfterBlock, contains(peerId));
        expect(visibleAfterBlock, isNot(contains(viewerId)));

        await writer.execute(
          '''DELETE FROM public.user_block '''
          '''WHERE blocker_id = '$viewerId' AND blocked_id = '$peerId' ''',
        );
        await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$peerId', '$viewerId', '$viewerId')
ON CONFLICT DO NOTHING
''');

        final visibleAfterReverse = await _queryHiddenAvailabilityUserIds(
          writer,
          session,
        );
        expect(visibleAfterReverse, contains(peerId));
        expect(visibleAfterReverse, isNot(contains(viewerId)));
      },
      skip: skipReason,
    );

    test(
      'Hasura select filter hides expired pause-only rows but keeps limited+past',
      () async {
        await migrateDbSchema(writer);

        const viewerId = 'Um0148read';
        final session = _sessionJson(viewerId);

        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('$viewerId', 'Reader', 'pk-read'),
  ('Um0148pausePast', 'Pause past', 'pk-pp'),
  ('Um0148pauseFuture', 'Pause future', 'pk-pf'),
  ('Um0148limitedPast', 'Limited past', 'pk-lp')
ON CONFLICT DO NOTHING
''');

        final utcToday = await writer.execute(r'''
SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date AS today_utc
''');
        final todayUtc = utcToday.single.single as DateTime;
        final yesterday = todayUtc.subtract(const Duration(days: 1));
        final tomorrow = todayUtc.add(const Duration(days: 1));
        final yesterdayStr = _isoDate(yesterday);
        final tomorrowStr = _isoDate(tomorrow);

        await writer.execute('''
INSERT INTO public.user_availability (user_id, is_limited, resume_on)
VALUES
  ('Um0148pausePast', false, '$yesterdayStr'),
  ('Um0148pauseFuture', false, '$tomorrowStr'),
  ('Um0148limitedPast', true, '$yesterdayStr')
ON CONFLICT DO NOTHING
''');

        final visible = await _queryHasuraVisibleAvailabilityUserIds(
          writer,
          session,
        );
        expect(visible, isNot(contains('Um0148pausePast')));
        expect(visible, contains('Um0148pauseFuture'));
        expect(visible, contains('Um0148limitedPast'));
      },
      skip: skipReason,
    );

    test(
      'Hasura now() filter matches UTC calendar date on this connection',
      () async {
        await migrateDbSchema(writer);

        final parity = await writer.execute(r'''
WITH samples AS (
  SELECT
    d.resume_on > now() AS hasura_style,
    d.resume_on > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date AS utc_style
  FROM (
    VALUES
      (DATE '2020-01-01'),
      ((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date - 1),
      ((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date),
      ((CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date + 1)
  ) AS d(resume_on)
)
SELECT
  current_setting('TimeZone') AS tz,
  count(*) FILTER (
    WHERE hasura_style IS DISTINCT FROM utc_style
  )::int AS mismatch_count
FROM samples
''');
        expect(
          parity.single[1],
          0,
          reason:
              'Hasura resume_on > now() must agree with UTC calendar date; '
              'connection TimeZone was ${parity.single[0]}',
        );
        expect(parity.single[0], 'UTC');
      },
      skip: skipReason,
    );

    test(
      'upgrade from m0147 applies user_availability schema',
      () async {
        await migrateDbSchema(writer);
        await _rollBackM0148ForTest(writer);

        await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Um0148upg', 'Upgrade', 'pk-upg')
ON CONFLICT DO NOTHING
''');

        for (final statement in m0148.statements) {
          await writer.execute(statement);
        }
        await writer.execute(
          "INSERT INTO public.schema_version (version, applied_at) "
          "VALUES ('0148', now()) "
          'ON CONFLICT DO NOTHING',
        );

        await _expectM0148Schema(writer);

        await writer.execute(r'''
INSERT INTO public.user_availability (user_id, resume_on)
VALUES ('Um0148upg', CURRENT_DATE + 3)
''');
        final row = await writer.execute(
          '''SELECT is_limited, resume_on IS NOT NULL '''
          '''FROM public.user_availability WHERE user_id = 'Um0148upg' ''',
        );
        expect(row.single[0], false);
        expect(row.single[1], true);
      },
      skip: skipReason,
    );

    test(
      'Hasura metadata exposes only public columns and omits updated_at',
      () {
        final metadataFile = File(
          '${Directory.current.path}/../../hasura/metadata.json',
        );
        final metadata =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        final tables =
            (metadata['metadata'] as Map<String, dynamic>)['sources'][0]['tables']
                as List<dynamic>;
        final availability = tables.cast<Map<String, dynamic>>().firstWhere(
          (entry) =>
              (entry['table'] as Map<String, dynamic>)['name'] ==
              'user_availability',
        );
        final permission =
            (availability['select_permissions'] as List<dynamic>).single
                as Map<String, dynamic>;
        final columns =
            ((permission['permission'] as Map<String, dynamic>)['columns']
                    as List<dynamic>)
                .cast<String>();
        expect(columns, ['is_limited', 'resume_on', 'user_id']);
        expect(columns, isNot(contains('updated_at')));
      },
    );
  });
}

Future<void> _expectM0148Schema(Connection writer) async {
  final persistence = await writer.execute(r'''
SELECT relpersistence::text
FROM pg_class
WHERE relname = 'user_availability'
  AND relnamespace = 'public'::regnamespace
''');
  expect(persistence.single.single, 'p');

  final columns = await writer.execute(r'''
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_availability'
ORDER BY column_name
''');
  expect(
    columns.map((r) => r[0]).toList(),
    ['is_limited', 'resume_on', 'updated_at', 'user_id'],
  );
  final isLimited = columns.firstWhere((r) => r[0] == 'is_limited');
  expect(isLimited[2], 'NO');
  expect(isLimited[3]?.toString(), contains('false'));
  final resumeOn = columns.firstWhere((r) => r[0] == 'resume_on');
  expect(resumeOn[2], 'YES');
  final updatedAt = columns.firstWhere((r) => r[0] == 'updated_at');
  expect(updatedAt[2], 'NO');

  final check = await writer.execute(r'''
SELECT conname
FROM pg_constraint
WHERE conname = 'user_availability_not_empty'
''');
  expect(check, hasLength(1));

  final indexes = await writer.execute(r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname = 'user_availability_resume_on_idx'
''');
  expect(indexes, hasLength(1));

  final fn = await writer.execute(r'''
SELECT count(*)::int
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'user_availability_hidden_for_viewer'
''');
  expect(fn.single.single, 1);

  final triggers = await writer.execute(r'''
SELECT count(*)::int
FROM pg_trigger
WHERE tgrelid = 'public.user_availability'::regclass
  AND NOT tgisinternal
''');
  expect(triggers.single.single, 0);
}

Future<Set<String>> _queryVisibleAvailabilityUserIds(
  Connection writer,
  String sessionJson,
) async {
  final rows = await writer.execute('''
SELECT ua.user_id
FROM public.user_availability ua
WHERE NOT public.user_availability_hidden_for_viewer(ua, '$sessionJson'::json)
ORDER BY ua.user_id
''');
  return rows.map((row) => row[0] as String).toSet();
}

Future<Set<String>> _queryHiddenAvailabilityUserIds(
  Connection writer,
  String sessionJson,
) async {
  final rows = await writer.execute('''
SELECT ua.user_id
FROM public.user_availability ua
WHERE public.user_availability_hidden_for_viewer(ua, '$sessionJson'::json)
ORDER BY ua.user_id
''');
  return rows.map((row) => row[0] as String).toSet();
}

Future<Set<String>> _queryHasuraVisibleAvailabilityUserIds(
  Connection writer,
  String sessionJson,
) async {
  final rows = await writer.execute('''
SELECT ua.user_id
FROM public.user_availability ua
WHERE NOT public.user_availability_hidden_for_viewer(ua, '$sessionJson'::json)
  AND (ua.is_limited OR ua.resume_on > now())
ORDER BY ua.user_id
''');
  return rows.map((row) => row[0] as String).toSet();
}

String _sessionJson(String viewerId) =>
    '{"x-hasura-user-id": "$viewerId"}';

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<void> _rollBackM0148ForTest(Connection connection) async {
  for (final statement in const [
    'DROP FUNCTION IF EXISTS public.user_availability_hidden_for_viewer(public.user_availability, json)',
    'DROP INDEX IF EXISTS public.user_availability_resume_on_idx',
    'DROP TABLE IF EXISTS public.user_availability',
    "DELETE FROM public.schema_version WHERE version = '0148'",
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
        Platform.environment['TENTURA_USER_AVAILABILITY_MIGRATION_TEST_DB'] ??
        'tentura_test_uavail_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_USER_AVAILABILITY_MIGRATION_TEST_DB',
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
