@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';
import '../../support/m0201_clamp_mr_harness.dart';

/// P0.1 (mr): projected trust must never publish a negative weight to MeritRank
/// except for the B1 ban wall. Post-m0202 publication reads `target_w`
/// (clamped non-negative outside a block; m0205 makes a block publish -1).
const _alice = m0201ClampMrAliceId;
const _bob = m0201ClampMrBobId;

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
      await m0201ClampMrPrepareEmptyPairFixture(database);
    });

    tearDown(() async {
      await m0201ClampMrCleanup(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('m0201 clamp published MR weight', () {
    test(
      'non-positive effective weight publishes 0 to MR (prev_sent_weight)',
      () async {
        await _seedPositivePair(database);
        await _publishTargetToMr(database, _alice, _bob);
        expect(await _readPrevSent(database, _alice, _bob), greaterThan(0));

        await database.customStatement('''
DELETE FROM public.trust_evidence
WHERE subject_user_id = '$_alice' AND object_user_id = '$_bob'
''');
        await _project(database, _alice, _bob);
        final edge = await _readEdge(database, _alice, _bob);
        expect(edge, isNotNull);
        expect(edge!.trustW, lessThanOrEqualTo(0));
        expect(edge.targetW, closeTo(0, 1e-9));

        await _publishTargetToMr(database, _alice, _bob);
        expect(
          await _readPrevSent(database, _alice, _bob),
          closeTo(0, 1e-9),
        );
      },
      skip: skipReason,
    );

    test(
      'positive effective weight publishes its computed target to MR',
      () async {
        await _insertEvidence(
          database,
          _alice,
          _bob,
          kind: 2,
          count: 2,
          sourceKey: 'm0201-mr:pos:$_alice:$_bob',
        );
        await _project(database, _alice, _bob);
        final edge = await _readEdge(database, _alice, _bob);
        expect(edge, isNotNull);
        expect(edge!.trustW, greaterThan(0));
        expect(edge.targetW, closeTo(edge.trustW, 1e-6));

        await _publishTargetToMr(database, _alice, _bob);
        final published = await _readPrevSent(database, _alice, _bob);
        expect(published, closeTo(edge.targetW, 1e-6));
        expect(published, greaterThan(0.01));
      },
      skip: skipReason,
    );

    test(
      'blocked pair with positive effective weight publishes -1 (ban wall) to MR',
      () async {
        await _seedPositivePair(database);
        await database.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_alice', '$_bob', '$_bob')
ON CONFLICT DO NOTHING
''');
        await _project(database, _alice, _bob);
        final edge = await _readEdge(database, _alice, _bob);
        expect(edge, isNotNull, reason: 'B1: a ban wall keeps the edge row');
        expect(edge!.targetW, closeTo(-1, 1e-9));

        await _publishTargetToMr(database, _alice, _bob);
        expect(
          await _readPrevSent(database, _alice, _bob),
          closeTo(-1, 1e-9),
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedPositivePair(TenturaDb db) async {
  await _insertEvidence(
    db,
    _alice,
    _bob,
    kind: 2,
    count: 2,
    sourceKey: 'm0201-mr:seed:$_alice:$_bob',
  );
  await _project(db, _alice, _bob);
}

Future<void> _insertEvidence(
  TenturaDb db,
  String subject,
  String object, {
  required int kind,
  required double count,
  required String sourceKey,
}) async {
  await db.customStatement(
    '''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES ('$sourceKey', '$subject', '$object', $kind, $count, '$sourceKey')
''',
  );
}

Future<void> _project(TenturaDb db, String subject, String object) async {
  await db.customSelect(
    r'SELECT public.trust_project_pair($1, $2)',
    variables: [Variable<String>(subject), Variable<String>(object)],
  ).getSingle();
}

Future<void> _publishTargetToMr(
  TenturaDb db,
  String subject,
  String object,
) async {
  await db.customStatement('''
SELECT mr_put_edge(subject, object, target_w, ''::text, 0)
FROM public.user_trust_edge
WHERE subject = '$subject' AND object = '$object'
''');
  await db.customStatement('''
UPDATE public.user_trust_edge
SET prev_sent_weight = target_w, updated_at = now()
WHERE subject = '$subject' AND object = '$object'
''');
}

Future<({double trustW, double targetW})?> _readEdge(
  TenturaDb db,
  String subject,
  String object,
) async {
  final rows = await db.customSelect(
    r'''
SELECT trust_w, target_w
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
    variables: [
      Variable<String>(subject),
      Variable<String>(object),
    ],
  ).get();
  if (rows.isEmpty) return null;
  final row = rows.single;
  return (
    trustW: row.read<double>('trust_w'),
    targetW: row.read<double>('target_w'),
  );
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
  ).getSingleOrNull();
  return row?.read<double>('prev_sent_weight') ?? 0;
}
