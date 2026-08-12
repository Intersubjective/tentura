@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

const _obs = 'Um0143obs1';
const _sub = 'Um0143sub1';
const _tag = 'transport';
const _kOut = 2.0;
const _hlOut = 365.0 * 86400.0;
const _hlSeed = 90.0 * 86400.0;
const _windowMonths = 24;

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0143 capability evidence SQL functions', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      await _seedUsers(writer);
    });

    tearDown(() async {
      try {
        await writer.execute('ROLLBACK');
      } on Object {
        // No open transaction.
      }
      await writer.execute(
        "DELETE FROM public.person_capability_event "
        "WHERE observer_user_id LIKE 'Um0143%'",
      );
      await writer.execute(
        "DELETE FROM public.capability_evidence_edge "
        "WHERE observer_user_id LIKE 'Um0143%'",
      );
      await writer.execute(
        "DELETE FROM public.capability_evidence_generation "
        "WHERE observer_user_id LIKE 'Um0143%'",
      );
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'fresh migration and m0142-to-m0143 upgrade install callable functions',
      () async {
        await _expectA3Functions(writer);

        await _rollBackM0143ForTest(writer);
        await _expectA3FunctionsAbsent(writer);

        for (final statement in m0143.statements) {
          await writer.execute(statement);
        }
        await writer.execute(
          "INSERT INTO public.schema_version (version, applied_at) "
          "VALUES ('0143', now()) "
          'ON CONFLICT DO NOTHING',
        );
        await _expectA3Functions(writer);

        final bump1 = await writer.execute(
          "SELECT public.cap_generation_bump('$_obs', '$_sub', '$_tag')",
        );
        expect(bump1.single.single, 1);

        final bump2 = await writer.execute(
          "SELECT public.cap_generation_bump('$_obs', '$_sub', '$_tag')",
        );
        expect(bump2.single.single, 2);

        final genRows = await writer.execute(r'''
SELECT observer_user_id, subject_user_id, tag_slug, generation
FROM public.capability_evidence_generation
WHERE observer_user_id = 'Um0143obs1'
  AND subject_user_id = 'Um0143sub1'
  AND tag_slug = 'transport'
''');
        expect(genRows.length, 1);
        expect(genRows.single[0], 'Um0143obs1');
        expect(genRows.single[1], 'Um0143sub1');
        expect(genRows.single[2], 'transport');
        expect(genRows.single[3], 2);
      },
      skip: skipReason,
    );

    test(
      'one fresh source-3 row yields cap_strength about 1/3; three about 0.60',
      () async {
        await _insertEvent(
          writer,
          id: 'Um0143e1',
          sourceType: 3,
        );
        await _rebuild(writer);

        final one = await _effectiveOutStrength(writer);
        expect(one, closeTo(1 / 3, 1e-4));

        for (var i = 2; i <= 3; i++) {
          await _insertEvent(
            writer,
            id: 'Um0143e$i',
            sourceType: 3,
          );
        }
        await _rebuild(writer);

        final three = await _effectiveOutStrength(writer);
        expect(three, closeTo(0.60, 1e-4));
      },
      skip: skipReason,
    );

    test(
      'source 1 and 4 contribute only to seed; source 2/negative/deleted excluded',
      () async {
        await _insertEvent(writer, id: 'Um0143fwd', sourceType: 1);
        await _insertEvent(
          writer,
          id: 'Um0143seed',
          sourceType: 4,
          tagSlug: 'pets',
        );
        await _insertEvent(writer, id: 'Um0143role', sourceType: 2);
        await _insertEvent(
          writer,
          id: 'Um0143neg',
          sourceType: 3,
          isNegative: true,
        );
        await _insertEvent(
          writer,
          id: 'Um0143del',
          sourceType: 3,
          deletedAt: '2026-01-01T00:00:00Z',
        );
        await _rebuild(writer);
        await writer.execute(
          "SELECT public.cap_cell_rebuild("
          "'$_obs', '$_sub', 'pets', $_windowMonths, $_hlOut, $_hlSeed)",
        );

        final cell = await _readCell(writer);
        expect(cell.sOut, 0);
        expect(cell.sSeed, closeTo(1.0, 1e-4));

        final pets = await writer.execute(r'''
SELECT s_out, s_seed
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0143obs1'
  AND subject_user_id = 'Um0143sub1'
  AND tag_slug = 'pets'
''');
        expect(pets.single[0], 0);
        expect(pets.single[1], closeTo(1.0, 1e-9));
      },
      skip: skipReason,
    );

    test('rows beyond 24 months do not contribute', () async {
      await writer.execute('BEGIN');
      await _insertEvent(
        writer,
        id: 'Um0143old',
        sourceType: 3,
        createdAt: '2020-01-01T00:00:00Z',
      );
      await writer.execute(r'''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type,
  visibility, note, is_negative, created_at
) VALUES (
  'Um0143new', 'Um0143sub1', 'Um0143obs1', 'transport', 3,
  0, '', false, now() - interval '1 day'
)
''');
      await _rebuild(writer);

      final cell = await _readCell(writer);
      expect(cell.sOut, closeTo(1.0, 0.01));
      expect(cell.sSeed, 0);
      await writer.execute('COMMIT');
    }, skip: skipReason);

    test(
      'five rebuilds of the same cell leave effective strength within 1e-9',
      () async {
        await _insertEvent(writer, id: 'Um0143eq', sourceType: 3);
        await _rebuild(writer);
        final baseline = await _effectiveOutStrength(writer);

        for (var i = 0; i < 5; i++) {
          await _rebuild(writer);
        }
        final after = await _effectiveOutStrength(writer);
        expect(after - baseline, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'event exactly one 365-day half-life old has about 0.5 accumulated mass',
      () async {
        await writer.execute('BEGIN');
        await writer.execute(r'''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type,
  visibility, note, is_negative, created_at
) VALUES (
  'Um0143hl', 'Um0143sub1', 'Um0143obs1', 'transport', 3,
  0, '', false, now() - interval '365 days'
)
''');
        await _rebuild(writer);

        final cell = await _readCell(writer);
        expect(cell.sOut, closeTo(0.5, 1e-4));
        await writer.execute('COMMIT');
      },
      skip: skipReason,
    );

    test(
      'leap-day window uses created_at + months, not inverse cutoff',
      () async {
        const createdAt = '2024-02-29T00:00:00Z';
        const referenceNow = '2026-02-28T00:00:00Z';
        const windowMonths = 24;

        final intended = await writer.execute(
          "SELECT ("
          "'$createdAt'::timestamptz "
          "+ make_interval(months => $windowMonths)) "
          "> '$referenceNow'::timestamptz",
        );
        final flawed = await writer.execute(
          "SELECT ("
          "'$createdAt'::timestamptz) "
          "> ('$referenceNow'::timestamptz "
          "- make_interval(months => $windowMonths))",
        );
        expect(intended.single.single, isFalse);
        expect(flawed.single.single, isTrue);

        await _insertEvent(
          writer,
          id: 'Um0143leap',
          sourceType: 3,
          createdAt: createdAt,
        );
        await _rebuild(writer);

        final rows = await writer.execute(r'''
SELECT count(*)::int
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0143obs1'
  AND subject_user_id = 'Um0143sub1'
  AND tag_slug = 'transport'
''');
        expect(rows.single.single, 0);
      },
      skip: skipReason,
    );

    test(
      '31st-of-month window uses created_at + months, not inverse cutoff',
      () async {
        const createdAt = '2024-01-31T00:00:00Z';
        const referenceNow = '2024-02-29T00:00:00Z';
        const windowMonths = 1;

        final intended = await writer.execute(
          "SELECT ("
          "'$createdAt'::timestamptz "
          "+ make_interval(months => $windowMonths)) "
          "> '$referenceNow'::timestamptz",
        );
        final flawed = await writer.execute(
          "SELECT ("
          "'$createdAt'::timestamptz) "
          "> ('$referenceNow'::timestamptz "
          "- make_interval(months => $windowMonths))",
        );
        expect(intended.single.single, isFalse);
        expect(flawed.single.single, isTrue);

        await _insertEvent(
          writer,
          id: 'Um014331st',
          sourceType: 3,
          createdAt: createdAt,
        );
        await _rebuild(writer);

        final rows = await writer.execute(r'''
SELECT count(*)::int
FROM public.capability_evidence_edge
WHERE observer_user_id = 'Um0143obs1'
  AND subject_user_id = 'Um0143sub1'
  AND tag_slug = 'transport'
''');
        expect(rows.single.single, 0);
      },
      skip: skipReason,
    );

    test(
      'two sessions rebuilding the same triple serialize on the advisory lock',
      () async {
        await _insertEvent(writer, id: 'Um0143lock', sourceType: 3);

        final locker = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        final waiter = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );

        try {
          await locker.execute('BEGIN');
          await locker.execute(
            "SELECT public.cap_cell_rebuild("
            "'$_obs', '$_sub', '$_tag', $_windowMonths, $_hlOut, $_hlSeed)",
          );

          var waiterFinished = false;
          final waiterFuture = () async {
            await waiter.execute('BEGIN');
            await waiter.execute(
              "SELECT public.cap_cell_rebuild("
              "'$_obs', '$_sub', '$_tag', $_windowMonths, $_hlOut, $_hlSeed)",
            );
            await waiter.execute('COMMIT');
            waiterFinished = true;
          }();

          await Future<void>.delayed(const Duration(milliseconds: 400));
          expect(waiterFinished, isFalse);

          await locker.execute('COMMIT');
          await waiterFuture.timeout(const Duration(seconds: 10));
          expect(waiterFinished, isTrue);
        } finally {
          await locker.close();
          await waiter.close();
        }
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedUsers(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Um0143obs1', 'Observer', 'pk-obs'),
  ('Um0143sub1', 'Subject', 'pk-sub')
ON CONFLICT DO NOTHING
''');
}

Future<void> _insertEvent(
  Connection writer, {
  required String id,
  required int sourceType,
  String tagSlug = _tag,
  String? createdAt,
  bool isNegative = false,
  String? deletedAt,
}) async {
  final createdClause = createdAt == null
      ? 'DEFAULT'
      : "'$createdAt'::timestamptz";
  final deletedClause = deletedAt == null
      ? 'NULL'
      : "'$deletedAt'::timestamptz";
  await writer.execute(
    '''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type,
  visibility, note, is_negative, created_at, deleted_at
) VALUES (
  '$id', '$_sub', '$_obs', '$tagSlug', $sourceType,
  0, '', $isNegative, $createdClause, $deletedClause
)
''',
  );
}

Future<void> _rebuild(Connection writer) async {
  await writer.execute(
    "SELECT public.cap_cell_rebuild("
    "'$_obs', '$_sub', '$_tag', $_windowMonths, $_hlOut, $_hlSeed)",
  );
}

Future<double> _effectiveOutStrength(Connection writer) async {
  final row = await writer.execute(
    "SELECT public.cap_strength(s_out, $_kOut, anchor_at, $_hlOut) "
    "FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$_obs' "
    "AND subject_user_id = '$_sub' "
    "AND tag_slug = '$_tag'",
  );
  return (row.single.single as num).toDouble();
}

Future<_CellRow> _readCell(Connection writer) async {
  final row = await writer.execute(
    "SELECT s_out, s_seed FROM public.capability_evidence_edge "
    "WHERE observer_user_id = '$_obs' "
    "AND subject_user_id = '$_sub' "
    "AND tag_slug = '$_tag'",
  );
  return _CellRow(
    sOut: (row.single[0] as num).toDouble(),
    sSeed: (row.single[1] as num).toDouble(),
  );
}

Future<void> _expectA3Functions(Connection writer) async {
  final names = await writer.execute(r'''
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN (
    'cap_strength',
    'cap_cell_lock',
    'cap_generation_bump',
    'cap_cell_rebuild'
  )
ORDER BY proname
''');
  expect(
    names.map((r) => r[0]).toList(),
    [
      'cap_cell_lock',
      'cap_cell_rebuild',
      'cap_generation_bump',
      'cap_strength',
    ],
  );

  final volatility = await writer.execute(r'''
SELECT p.provolatile = 's' AS is_stable
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'cap_strength'
''');
  expect(volatility.single.single, isTrue);

  await writer.execute(
    "SELECT public.cap_strength(1.0, $_kOut, now(), $_hlOut)",
  );
  await writer.execute(
    "SELECT public.cap_cell_lock('$_obs', '$_sub', '$_tag')",
  );

  final rebuildDef = await writer.execute(r'''
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'cap_cell_rebuild'
''');
  final def = rebuildDef.single.single as String;
  expect(
    def.contains('e.created_at + make_interval(months => _window_months) > now()'),
    isTrue,
    reason: 'installed cap_cell_rebuild must use forward month addition eligibility',
  );
  expect(
    def.contains('now() -'),
    isFalse,
    reason: 'installed cap_cell_rebuild must not use inverse now()-interval cutoff',
  );
  expect(
    def.contains('_cutoff'),
    isFalse,
    reason: 'installed cap_cell_rebuild must not use a _cutoff variable',
  );
}

Future<void> _expectA3FunctionsAbsent(Connection writer) async {
  final names = await writer.execute(r'''
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN (
    'cap_strength',
    'cap_cell_lock',
    'cap_generation_bump',
    'cap_cell_rebuild'
  )
''');
  expect(names, isEmpty);
}

Future<void> _rollBackM0143ForTest(Connection connection) async {
  for (final statement in const [
    'DROP FUNCTION IF EXISTS public.cap_cell_rebuild(text, text, text, integer, double precision, double precision)',
    'DROP FUNCTION IF EXISTS public.cap_generation_bump(text, text, text)',
    'DROP FUNCTION IF EXISTS public.cap_cell_lock(text, text, text)',
    'DROP FUNCTION IF EXISTS public.cap_strength(double precision, double precision, timestamptz, double precision)',
    "DELETE FROM public.schema_version WHERE version = '0143'",
  ]) {
    await connection.execute(statement);
  }
}

class _CellRow {
  const _CellRow({required this.sOut, required this.sSeed});

  final double sOut;
  final double sSeed;
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
        Platform.environment['TENTURA_M0143_MIGRATION_TEST_DB'] ??
        'tentura_test_m0143_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_M0143_MIGRATION_TEST_DB',
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
