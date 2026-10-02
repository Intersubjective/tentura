@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// P0.1 pg-only, post-m0202 shape: projection never publishes in-transaction
/// (a materially changed target lands on `trust_publish_queue` with
/// `prev_sent_weight` untouched), and the projected target weight is clamped
/// to non-negative — a block forces it to 0.
const _alice = 'Um0201pgalice';
const _bob = 'Um0201pgbob01';
const _allIds = [_alice, _bob];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0201_CLAMP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0201_clamp_pg',
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

  test(
    'trust_project_pair enqueues publication instead of sending in-transaction',
    () async {
      await _insertEvidence(database, _alice, _bob);
      await _project(database, _alice, _bob);

      final edge = await _readEdge(database, _alice, _bob);
      expect(edge, isNotNull);
      expect(edge!.trustW, greaterThan(0));
      expect(edge.targetW, greaterThan(0));
      expect(
        edge.prevSentWeight,
        0,
        reason: 'projection must not publish; the queue is the only path',
      );

      final queued = await database
          .customSelect(
            'SELECT count(*)::int AS c FROM public.trust_publish_queue '
            "WHERE subject_user_id = '$_alice' AND object_user_id = '$_bob'",
          )
          .getSingle();
      expect(queued.read<int>('c'), 1);
    },
    skip: skipReason,
  );

  test(
    'trust_project_pair projects the -1 wall under a block',
    () async {
      await _insertEvidence(database, _alice, _bob);
      await _project(database, _alice, _bob);
      expect(await _readEdge(database, _alice, _bob), isNotNull);

      await database.customStatement(
        "INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) "
        "VALUES ('$_alice', '$_bob', '$_alice')",
      );
      await _project(database, _alice, _bob);

      // B1: a block raises the wall (target -1) even though nothing was
      // ever sent, and the sign change is queued for publication.
      expect((await _readEdge(database, _alice, _bob))?.targetW, -1);
      final queued = await database
          .customSelect(
            'SELECT count(*)::int AS c FROM public.trust_publish_queue '
            "WHERE subject_user_id = '$_alice' AND object_user_id = '$_bob'",
          )
          .getSingle();
      expect(queued.read<int>('c'), 1);
    },
    skip: skipReason,
  );
}

Future<void> _insertEvidence(
  TenturaDb db,
  String subjectId,
  String objectId,
) => db.customStatement(
  '''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES ('m0201-ev-$subjectId-$objectId', '$subjectId', '$objectId', 2, 1,
        'm0201:$subjectId:$objectId')
''',
);

Future<void> _project(TenturaDb db, String subject, String object) => db
    .customSelect(
      r'SELECT public.trust_project_pair($1, $2)',
      variables: [Variable<String>(subject), Variable<String>(object)],
    )
    .getSingle();

Future<({double trustW, double targetW, double prevSentWeight})?> _readEdge(
  TenturaDb db,
  String subject,
  String object,
) async {
  final rows = await db
      .customSelect(
        r'''
SELECT trust_w, target_w, prev_sent_weight
FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
        variables: [
          Variable<String>(subject),
          Variable<String>(object),
        ],
      )
      .get();
  if (rows.isEmpty) return null;
  final row = rows.single;
  return (
    trustW: row.read<double>('trust_w'),
    targetW: row.read<double>('target_w'),
    prevSentWeight: row.read<double>('prev_sent_weight'),
  );
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _cleanup(TenturaDb db) async {
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_block '
    'WHERE blocker_id IN ($idList) OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
}
