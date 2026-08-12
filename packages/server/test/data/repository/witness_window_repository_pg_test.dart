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
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late WitnessWindowRepository repo;
  late MeritrankRepository meritRank;

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
      repo = WitnessWindowRepository(database);
      meritRank = MeritrankRepository(database);
    });

    setUp(() async {
      await _cleanup(database);
      await _resetEpoch(database);
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

Future<void> _clearMrEdge(TenturaDb db, String subject, String object) =>
    db.customStatement(
      "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
    );

Future<void> _cleanup(TenturaDb db) async {
  for (final id in _allIds) {
    if (id == _ego) continue;
    await _clearMrEdge(db, _ego, id);
    await _clearMrEdge(db, id, _ego);
  }
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
        Platform.environment['TENTURA_WITNESS_WINDOW_REPO_TEST_DB'] ??
        'tentura_test_witness_window_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_WITNESS_WINDOW_REPO_TEST_DB',
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
