@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/domain/entity/forward_attribution_method.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasAttributionTable(probe)) {
        skipReason = 'forward_decision_attribution missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late ForwardAttributionRepository repo;

  const batchA = 'FBattrbatchA';
  const batchB = 'FBattrbatchB';
  const edge1 = 'FEattr000001';
  const edge2 = 'FEattr000002';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      repo = ForwardAttributionRepository(db);
      final keyA = pgTestPublicKey('fattr', 1);
      final keyB = pgTestPublicKey('fattr', 2);
      final keyC = pgTestPublicKey('fattr', 3);
      await db.customStatement(
        r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Ufattrauth01', 'Author', $1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufattrsend01', 'Sender', $2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ufattrrecip1', 'Recipient', $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        [keyA, keyB, keyC],
      );
      await db.customStatement(
        '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('Bfattr000001', 'Ufattrauth01', 'attr test', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
      await db.customStatement(
        '''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, created_at)
VALUES
  ('$edge1', 'Bfattr000001', 'Ufattrsend01', 'Ufattrrecip1', '2026-01-01T00:00:00Z'),
  ('$edge2', 'Bfattr000001', 'Ufattrauth01', 'Ufattrsend01', '2026-01-02T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.forward_decision_attribution WHERE child_forward_batch_id LIKE 'FBattr%'",
      );
    });

    tearDownAll(() async {
      await db.customStatement(
        "DELETE FROM public.forward_decision_attribution WHERE child_forward_batch_id LIKE 'FBattr%'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon_forward_edge WHERE beacon_id = 'Bfattr000001'",
      );
      await db.customStatement(
        "DELETE FROM public.beacon WHERE id = 'Bfattr000001'",
      );
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id LIKE 'Ufattr%' ''',
      );
      await db.close();
    });
  }

  test('record explicit single parent and fetch by batch', () async {
    await repo.record(
      batchId: batchA,
      weightByParentEdgeId: {edge1: 1.0},
      method: ForwardAttributionMethod.explicitSingle,
    );
    final rows = await repo.fetchByBatchIds([batchA]);
    expect(rows, hasLength(1));
    expect(rows.first.parentForwardEdgeId, edge1);
    expect(rows.first.weight, closeTo(1.0, 1e-9));
    expect(rows.first.method, ForwardAttributionMethod.explicitSingle);
  }, skip: skipReason);

  test('record explicit multiple splits weight evenly', () async {
    await repo.record(
      batchId: batchB,
      weightByParentEdgeId: {edge1: 0.5, edge2: 0.5},
      method: ForwardAttributionMethod.explicitMultiple,
    );
    final rows = await repo.fetchByBatchIds([batchB]);
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.weight).fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
  }, skip: skipReason);

  test('empty weight map throws', () async {
    expect(
      () => repo.record(
        batchId: batchA,
        weightByParentEdgeId: {},
        method: ForwardAttributionMethod.explicitSingle,
      ),
      throwsArgumentError,
    );
  }, skip: skipReason);

  test('weights not summing to 1 throws', () async {
    expect(
      () => repo.record(
        batchId: batchA,
        weightByParentEdgeId: {edge1: 0.3},
        method: ForwardAttributionMethod.explicitSingle,
      ),
      throwsArgumentError,
    );
  }, skip: skipReason);

  test('duplicate insert is idempotent via ON CONFLICT DO NOTHING', () async {
    await repo.record(
      batchId: batchA,
      weightByParentEdgeId: {edge1: 1.0},
      method: ForwardAttributionMethod.explicitSingle,
    );
    await repo.record(
      batchId: batchA,
      weightByParentEdgeId: {edge1: 1.0},
      method: ForwardAttributionMethod.explicitSingle,
    );
    final count = await db.customSelect(
      "SELECT COUNT(*)::int AS c FROM forward_decision_attribution WHERE child_forward_batch_id = '$batchA'",
    ).getSingle();
    expect(count.read<int>('c'), 1);
  }, skip: skipReason);
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

Future<bool> _hasAttributionTable(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'forward_decision_attribution'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
