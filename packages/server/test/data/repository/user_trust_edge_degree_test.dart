@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_TRUST_EDGE_DEGREE_TEST_DB',
    defaultNamePrefix: 'tentura_test_uted',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;

  const aliceId = 'UdegAlice001';
  const bobId = 'UdegBob00001';
  const charlieId = 'UdegCharlie1';
  const allIds = [aliceId, bobId, charlieId];

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);

      Future<void> user(String id) => db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );

      Future<void> trustEdge(String subject, String object, double weight) =>
          db.customStatement(
            '''
INSERT INTO public.user_trust_edge (
  subject,
  object,
  prev_sent_weight,
  trust_w,
  wall_d,
  target_w,
  created_at,
  updated_at
) VALUES (
  '$subject',
  '$object',
  $weight,
  $weight,
  0,
  $weight,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  trust_w = EXCLUDED.trust_w,
  target_w = EXCLUDED.target_w,
  updated_at = EXCLUDED.updated_at
''',
          );

      for (final id in allIds) {
        await user(id);
      }
      await trustEdge(aliceId, bobId, 1);
      await trustEdge(aliceId, charlieId, -1);
      await trustEdge(bobId, charlieId, 1);
      await trustEdge(charlieId, bobId, 1);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test(
    'user_trust_edge_degree counts all edges or positive edges by sign',
    () async {
      if (skipReason != false) return;

      final aliceAll = await _degree(
        db,
        nodeId: aliceId,
        positiveOnly: false,
      );
      final alicePositive = await _degree(
        db,
        nodeId: aliceId,
        positiveOnly: true,
      );
      final bobPositive = await _degree(
        db,
        nodeId: bobId,
        positiveOnly: true,
      );

      expect(aliceAll, 2);
      expect(alicePositive, 1);
      expect(bobPositive, 2);
    },
    skip: skipReason,
  );

  test(
    'user_trust_edge_degree counts distinct neighbors, not directed rows, '
    'for a fully mutual relationship',
    () async {
      if (skipReason != false) return;

      // bob<->charlie is mutual (two directed rows, one neighbor): a naive
      // COUNT(*) over rows would report 3 for bob (alice, ->charlie,
      // charlie->), double-counting charlie.
      final bobAll = await _degree(
        db,
        nodeId: bobId,
        positiveOnly: false,
      );

      expect(bobAll, 2);
    },
    skip: skipReason,
  );
}

Future<int> _degree(
  TenturaDb db, {
  required String nodeId,
  required bool positiveOnly,
}) async {
  final row = await db
      .customSelect(
        'SELECT public.user_trust_edge_degree(\$1, \$2) AS degree',
        variables: [
          Variable<String>(nodeId),
          Variable<bool>(positiveOnly),
        ],
      )
      .getSingle();
  return row.read<int>('degree');
}
