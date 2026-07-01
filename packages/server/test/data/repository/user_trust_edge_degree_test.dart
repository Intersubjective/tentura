@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasUserTrustEdgeTable(probe)) {
        skipReason = 'user_trust_edge table missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const aliceId = 'UdegAlice001';
  const bobId = 'UdegBob00001';
  const charlieId = 'UdegCharlie1';
  const allIds = [aliceId, bobId, charlieId];

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());

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
  anchor_at,
  prev_sent_weight,
  created_at,
  updated_at
) VALUES (
  '$subject',
  '$object',
  '2026-01-01T00:00:00Z',
  $weight,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  prev_sent_weight = EXCLUDED.prev_sent_weight,
  anchor_at = EXCLUDED.anchor_at,
  updated_at = EXCLUDED.updated_at
''',
          );

      for (final id in allIds) {
        await user(id);
      }
      await trustEdge(aliceId, bobId, 1);
      await trustEdge(aliceId, charlieId, -1);
      await trustEdge(bobId, charlieId, 1);
    });

    tearDownAll(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement('''
DELETE FROM public.user_trust_edge WHERE subject IN ($idList)
  OR object IN ($idList)
''');
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ($idList)''',
      );
      await db.close();
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

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _hasUserTrustEdgeTable(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_trust_edge'
LIMIT 1
''',
  ).getSingleOrNull();
  return rows != null;
}
