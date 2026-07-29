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
      if (!await _hasGraphEdgesBetweenFunction(probe)) {
        skipReason = 'graph_edges_between function missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  if (skipReason == false) {
    setUp(() async {
      db = TenturaDb(_testEnv());
    });

    tearDown(() async {
      await db.close();
    });
  }

  test(
    'one-way A→B returns exactly one row',
    () async {
      if (skipReason != false) return;

      const aId = 'UgebtonewayA1';
      const bId = 'UgebtonewayB1';
      await _seedUsers(db, [aId, bId]);
      await _seedTrustEdge(db, subject: aId, object: bId, weight: 1);

      final rows = await _queryEdgesBetween(db, [aId, bId]);

      expect(rows, hasLength(1));
      expect(rows.single.src, aId);
      expect(rows.single.dst, bId);

      await _cleanupUsers(db, [aId, bId]);
    },
    skip: skipReason,
  );

  test(
    'reciprocal A→B and B→A returns two directed rows',
    () async {
      if (skipReason != false) return;

      const aId = 'UgebtrecipA01';
      const bId = 'UgebtrecipB01';
      await _seedUsers(db, [aId, bId]);
      await _seedTrustEdge(db, subject: aId, object: bId, weight: 1);
      await _seedTrustEdge(db, subject: bId, object: aId, weight: 1);

      final rows = await _queryEdgesBetween(db, [aId, bId]);

      expect(rows, hasLength(2));
      expect(
        rows.map((row) => (row.src, row.dst)).toSet(),
        {(aId, bId), (bId, aId)},
      );

      await _cleanupUsers(db, [aId, bId]);
    },
    skip: skipReason,
  );

  test(
    'transitive A→B→C returns both edges for [A,B,C] and none for [A,C]',
    () async {
      if (skipReason != false) return;

      const aId = 'UgebtransA001';
      const bId = 'UgebtransB001';
      const cId = 'UgebtransC001';
      await _seedUsers(db, [aId, bId, cId]);
      await _seedTrustEdge(db, subject: aId, object: bId, weight: 1);
      await _seedTrustEdge(db, subject: bId, object: cId, weight: 1);

      final allRows = await _queryEdgesBetween(db, [aId, bId, cId]);
      final endpointRows = await _queryEdgesBetween(db, [aId, cId]);

      expect(
        allRows.map((row) => (row.src, row.dst)).toSet(),
        {(aId, bId), (bId, cId)},
      );
      expect(endpointRows, isEmpty);

      await _cleanupUsers(db, [aId, bId, cId]);
    },
    skip: skipReason,
  );

  test(
    'cyclic A→B→C→A returns three rows and terminates',
    () async {
      if (skipReason != false) return;

      const aId = 'UgebtcyclicA1';
      const bId = 'UgebtcyclicB1';
      const cId = 'UgebtcyclicC1';
      await _seedUsers(db, [aId, bId, cId]);
      await _seedTrustEdge(db, subject: aId, object: bId, weight: 1);
      await _seedTrustEdge(db, subject: bId, object: cId, weight: 1);
      await _seedTrustEdge(db, subject: cId, object: aId, weight: 1);

      final rows = await _queryEdgesBetween(db, [aId, bId, cId]);

      expect(rows, hasLength(3));
      expect(
        rows.map((row) => (row.src, row.dst)).toSet(),
        {(aId, bId), (bId, cId), (cId, aId)},
      );

      await _cleanupUsers(db, [aId, bId, cId]);
    },
    skip: skipReason,
  );

  test(
    'positive_only=true filters out non-positive edges',
    () async {
      if (skipReason != false) return;

      const aId = 'UgebtposonlyA1';
      const bId = 'UgebtposonlyB1';
      await _seedUsers(db, [aId, bId]);
      await _seedTrustEdge(db, subject: aId, object: bId, weight: -1);

      final positiveRows = await _queryEdgesBetween(db, [aId, bId]);
      final allRows = await _queryEdgesBetween(
        db,
        [aId, bId],
        positiveOnly: false,
      );

      expect(positiveRows, isEmpty);
      expect(allRows, hasLength(1));
      expect(allRows.single.dstScore, -1);

      await _cleanupUsers(db, [aId, bId]);
    },
    skip: skipReason,
  );
}

typedef _GraphEdgeRow = ({
  String src,
  String dst,
  double dstScore,
});

Future<List<_GraphEdgeRow>> _queryEdgesBetween(
  TenturaDb db,
  List<String> nodeIds, {
  bool positiveOnly = true,
}) async {
  final arrayLiteral =
      'ARRAY[${nodeIds.map((id) => "'$id'").join(', ')}]::text[]';
  final rows = await db.customSelect(
    '''
SELECT src, dst, dst_score
FROM public.graph_edges_between($arrayLiteral, $positiveOnly)
ORDER BY src, dst
''',
  ).get();

  return [
    for (final row in rows)
      (
        src: row.read<String>('src'),
        dst: row.read<String>('dst'),
        dstScore: row.read<double>('dst_score'),
      ),
  ];
}

Future<void> _seedUsers(TenturaDb db, List<String> ids) async {
  for (final id in ids) {
    await db.customStatement(
      '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
    );
  }
}

Future<void> _seedTrustEdge(
  TenturaDb db, {
  required String subject,
  required String object,
  required double weight,
}) => db.customStatement(
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

Future<void> _cleanupUsers(TenturaDb db, List<String> ids) async {
  final idList = ids.map((id) => "'$id'").join(', ');
  await db.customStatement('''
DELETE FROM public.user_trust_edge WHERE subject IN ($idList)
  OR object IN ($idList)
''');
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
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

Future<bool> _hasGraphEdgesBetweenFunction(TenturaDb db) async {
  final rows = await db.customSelect(
    '''
SELECT 1
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'graph_edges_between'
LIMIT 1
''',
  ).getSingleOrNull();
  return rows != null;
}
