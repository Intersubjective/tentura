@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// P0.1: `trust_rebuild_effective_edge` must never publish a negative weight to
/// MeritRank (MR v0.11.0 treats negatives as walls). Clamped publication lands
/// in migration `m0201`.
const _alice = 'Um0201alice01';
const _bob = 'Um0201bob0001';
const _allIds = [_alice, _bob];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0201_CLAMP_MR_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0201_clamp_mr',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
    });

    setUp(() async {
      await _cleanup(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
    });

    tearDown(() async {
      await _cleanup(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('m0201 clamp published MR weight', () {
    test(
      'negative effective weight publishes 0 to MR (prev_sent_weight)',
      () async {
        await _applySource(database, _alice, _bob, 'very_good', 2);
        await _rebuild(database, _alice, _bob, epsilonOverride: -1);
        final positivePrev = await _readPrevSent(database, _alice, _bob);
        expect(positivePrev, greaterThan(0));

        await _applySource(database, _alice, _bob, 'very_bad', 3);
        final rawWeight = await _rebuild(database, _alice, _bob);
        expect(rawWeight, lessThan(0));

        expect(
          await _readPrevSent(database, _alice, _bob),
          closeTo(0, 1e-9),
        );
      },
      skip: skipReason,
    );

    test(
      'positive effective weight publishes its computed value to MR',
      () async {
        await _applySource(database, _alice, _bob, 'very_good', 2);
        final rawWeight = await _rebuild(
          database,
          _alice,
          _bob,
          epsilonOverride: -1,
        );
        expect(rawWeight, greaterThan(0));

        final published = await _readPrevSent(database, _alice, _bob);
        expect(published, closeTo(rawWeight, 1e-6));
        expect(published, greaterThan(0.01));
      },
      skip: skipReason,
    );

    test(
      'blocked pair with positive effective weight still publishes 0 to MR',
      () async {
        await _applySource(database, _alice, _bob, 'very_good', 2);
        await database.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_alice', '$_bob', '$_bob')
ON CONFLICT DO NOTHING
''');
        final rawWeight = await _rebuild(
          database,
          _alice,
          _bob,
          epsilonOverride: -1,
        );
        expect(rawWeight, greaterThan(0.01));

        final published = await _readPrevSent(database, _alice, _bob);
        expect(published, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );
  });
}

Future<void> _applySource(
  TenturaDb db,
  String subject,
  String object,
  String bin,
  double amount,
) async {
  await db.customStatement(
    r'''
SELECT trust_apply_source_evidence('personal', $1, $2, $3, $4)
''',
    [subject, object, bin, amount],
  );
}

Future<double> _rebuild(
  TenturaDb db,
  String subject,
  String object, {
  double? epsilonOverride,
}) async {
  final row = await db
      .customSelect(
        r'SELECT trust_rebuild_effective_edge($1, $2, $3) AS w',
        variables: [
          Variable<String>(subject),
          Variable<String>(object),
          Variable<double>(epsilonOverride ?? 0.1),
        ],
      )
      .getSingle();
  return row.read<double>('w');
}

Future<double> _readPrevSent(
  TenturaDb db,
  String subject,
  String object,
) async {
  final row = await db.customSelect(
    r'''
SELECT prev_sent_weight
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
    variables: [
      Variable<String>(subject),
      Variable<String>(object),
    ],
  ).getSingle();
  return row.read<double>('prev_sent_weight');
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _cleanup(TenturaDb db) async {
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
    'OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_source_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
}
