@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';
import 'package:tentura_server/env.dart';

const _ego = 'Ucapb2bego01';
const _ctx = '';
const _topK = 3;

const _allIds = [
  _ego,
  'Ucapb2bp01',
  'Ucapb2bp02',
  'Ucapb2bp03',
  'Ucapb2bp04',
  'Ucapb2bzero1',
];

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (skipReason == false) {
    final env = _testEnv();
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    try {
      if (!await _meritRankReady(connection)) {
        skipReason = 'mr_put_edge / person_visibility_peers missing';
      } else if (!await _hasWitnessWindowTable(connection)) {
        await connection.execute('SET check_function_bodies = false');
        await migrateDbSchema(connection);
      }
      if (skipReason == false && !await _hasWitnessWindowTable(connection)) {
        skipReason = 'ego_witness_window missing after migrateDbSchema';
      }
    } finally {
      await connection.close();
    }
  }

  late TenturaDb database;
  late WitnessWindowRepository repo;
  late MeritrankRepository meritRank;

  if (skipReason == false) {
    setUp(() async {
      database = TenturaDb(_testEnv());
      repo = WitnessWindowRepository(database);
      meritRank = MeritrankRepository(database);
      await meritRank.init();
      await _cleanup(database);
      await _resetEpoch(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
    });

    tearDown(() async {
      await _cleanup(database);
      await database.close();
    });
  }

  group('WitnessWindowRepository', () {
    test(
      'rawWindowFacts limits topPeers by topK but trustedScores are unbounded',
      () async {
        await _mrEdge(meritRank, _ego, 'Ucapb2bp01', 0.9);
        await _mrEdge(meritRank, _ego, 'Ucapb2bp02', 0.8);
        await _mrEdge(meritRank, _ego, 'Ucapb2bp03', 0.7);
        await _mrEdge(meritRank, _ego, 'Ucapb2bp04', 0.05);
        await _trustEdge(database, _ego, 'Ucapb2bp04');

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: _topK,
        );

        expect(facts.topPeers, hasLength(_topK));
        expect(
          facts.topPeers.map((p) => p.peerId),
          ['Ucapb2bp01', 'Ucapb2bp02', 'Ucapb2bp03'],
        );
        expect(facts.trustedScores, hasLength(1));
        expect(facts.trustedScores.single, greaterThan(0));
        expect(
          facts.topPeers.any((p) => p.peerId == 'Ucapb2bp04'),
          isFalse,
        );
      },
      skip: skipReason,
    );

    test(
      'rawWindowFacts excludes explicitly trusted zero-MR peers',
      () async {
        await _trustEdge(database, _ego, 'Ucapb2bzero1');
        await _mrEdge(meritRank, _ego, 'Ucapb2bp01', 0.5);

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: kCapWitnessWindowK,
        );

        expect(
          facts.topPeers.any((p) => p.peerId == 'Ucapb2bzero1'),
          isFalse,
        );
        expect(facts.trustedScores, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'storeWindow and cachedWindow round-trip at current epoch',
      () async {
        await _mrEdge(meritRank, _ego, 'Ucapb2bp01', 0.5);
        await _trustEdge(database, _ego, 'Ucapb2bp01');

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: kCapWitnessWindowK,
        );
        final weights = computeWitnessWeights(facts);

        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: weights,
        );

        final cached = await repo.cachedWindow(
          egoId: _ego,
          normalizedContext: _ctx,
        );
        expect(cached, hasLength(1));
        expect(cached.single.witnessUserId, 'Ucapb2bp01');
        expect(cached.single.admitted, isTrue);
        expect(cached.single.m, closeTo(1.0, 1e-4));
      },
      skip: skipReason,
    );

    test(
      'cachedWindow misses when mr_epoch is stale',
      () async {
        await _mrEdge(meritRank, _ego, 'Ucapb2bp01', 0.5);
        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: kCapWitnessWindowK,
        );
        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: computeWitnessWeights(facts),
        );

        await repo.bumpMrEpoch();

        final cached = await repo.cachedWindow(
          egoId: _ego,
          normalizedContext: _ctx,
        );
        expect(cached, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'cachedWindow misses when computed_at exceeds TTL',
      () async {
        await database.customStatement(
          r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, computed_at, mr_epoch
) VALUES (
  $1, $2, $3, 1.0, true,
  now() - make_interval(mins => $4::integer),
  (SELECT epoch FROM public.mr_publish_epoch WHERE id = true)
)
''',
          [
            _ego,
            _ctx,
            'Ucapb2bp01',
            kCapWindowTtlMinutes + 1,
          ],
        );

        final cached = await repo.cachedWindow(
          egoId: _ego,
          normalizedContext: _ctx,
        );
        expect(cached, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'storeWindow with empty weights clears prior cached rows',
      () async {
        await database.customStatement(
          r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, computed_at, mr_epoch
) VALUES (
  $1, $2, $3, 1.0, true, now(),
  (SELECT epoch FROM public.mr_publish_epoch WHERE id = true)
)
''',
          [_ego, _ctx, 'Ucapb2bp01'],
        );
        expect(await _windowRowCount(database), 1);

        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: const [],
        );

        expect(await _windowRowCount(database), 0);
        expect(
          await repo.cachedWindow(egoId: _ego, normalizedContext: _ctx),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      'invalidateFor removes rows where user is ego or witness',
      () async {
        await database.customStatement(
          r'''
INSERT INTO public.ego_witness_window (
  ego_user_id, context, witness_user_id, m, admitted, computed_at, mr_epoch
) VALUES
  ($1, $2, $3, 1.0, true, now(), 0),
  ($4, $2, $1, 0.5, false, now(), 0)
''',
          [_ego, _ctx, 'Ucapb2bp01', 'Ucapb2bp02'],
        );
        await repo.invalidateFor(userId: _ego);
        expect(await _windowRowCount(database), 0);
      },
      skip: skipReason,
    );
  });
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _trustEdge(TenturaDb db, String subject, String object) =>
    db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

Future<void> _mrEdge(
  MeritrankRepository meritRank,
  String subject,
  String object,
  double weight,
) => meritRank.putEdge(nodeA: subject, nodeB: object, weight: weight);

Future<void> _cleanup(TenturaDb db) async {
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.ego_witness_window '
    'WHERE ego_user_id IN ($idList) OR witness_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<void> _resetEpoch(TenturaDb db) => db.customStatement(
  r'UPDATE public.mr_publish_epoch SET epoch = 0 WHERE id = true',
);

Future<int> _windowRowCount(TenturaDb db) async {
  final row = await db
      .customSelect(
        r'''
SELECT count(*)::int AS c
FROM public.ego_witness_window
WHERE ego_user_id LIKE 'Ucapb2b%'
''',
      )
      .getSingle();
  return row.read<int>('c');
}

Future<bool> _meritRankReady(Connection connection) async {
  final rows = await connection.execute('''
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname = 'mr_put_edge') > 0
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'person_visibility_peers') > 0
  AS ready
''');
  return rows.single.single! as bool;
}

Future<bool> _hasWitnessWindowTable(Connection connection) async {
  final rows = await connection.execute(
    "SELECT to_regclass('public.ego_witness_window') IS NOT NULL AS ok",
  );
  return rows.single.single! as bool;
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
