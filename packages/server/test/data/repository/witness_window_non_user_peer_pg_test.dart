@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/capability/witness_window_policy.dart';

import '../../support/disposable_pg_target.dart';

const _ego = 'Ucapnuego01';
const _ctx = '';
const _topK = 3;

/// A MeritRank node that is not a user (verified contact / poll variant /
/// beacon activity event ids carry the `V` prefix).
const _nonUserNode = 'Vcapnunode01';

const _userPeers = [
  'Ucapnup01',
  'Ucapnup02',
  'Ucapnup03',
  'Ucapnup04',
];

const _allUserIds = [_ego, ..._userPeers];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WITNESS_WINDOW_NON_USER_PEER_TEST_DB',
    defaultNamePrefix: 'tentura_test_witness_window_non_user',
  );
  final reachable = await canReachPostgresAdmin(target);
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
      for (final id in _allUserIds) {
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

  group('WitnessWindowRepository with non-user MeritRank peers', () {
    test(
      'rawWindowFacts never returns a non-user node as a top peer',
      () async {
        await _mrEdge(meritRank, _ego, _nonUserNode, 0.9);
        await _mrEdge(meritRank, _ego, 'Ucapnup01', 0.5);

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: _topK,
        );

        expect(facts.topPeers.map((p) => p.peerId), ['Ucapnup01']);
      },
      skip: skipReason,
    );

    test(
      'rawWindowFacts topK counts only users when a non-user node outranks them',
      () async {
        // The non-user node has the strongest score, so if it were counted
        // against topK it would push the weakest user out of the window.
        await _mrEdge(meritRank, _ego, _nonUserNode, 0.95);
        await _mrEdge(meritRank, _ego, 'Ucapnup01', 0.9);
        await _mrEdge(meritRank, _ego, 'Ucapnup02', 0.5);
        await _mrEdge(meritRank, _ego, 'Ucapnup03', 0.1);
        await _mrEdge(meritRank, _ego, 'Ucapnup04', 0.02);

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: _topK,
        );

        expect(facts.topPeers, hasLength(_topK));
        expect(
          facts.topPeers.map((p) => p.peerId),
          ['Ucapnup01', 'Ucapnup02', 'Ucapnup03'],
        );
      },
      skip: skipReason,
    );

    test(
      'storeWindow succeeds for a window computed from a peer list '
      'that contains a non-user node',
      () async {
        await _mrEdge(meritRank, _ego, _nonUserNode, 0.9);
        await _mrEdge(meritRank, _ego, 'Ucapnup01', 0.5);
        await _trustEdge(database, _ego, 'Ucapnup01');

        final facts = await repo.rawWindowFacts(
          egoId: _ego,
          normalizedContext: _ctx,
          topK: _topK,
        );
        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: computeWitnessWeights(facts),
        );

        final cached = await repo.cachedWindow(
          egoId: _ego,
          normalizedContext: _ctx,
        );
        expect(cached.map((w) => w.witnessUserId), ['Ucapnup01']);
      },
      skip: skipReason,
    );

    test(
      'storeWindow drops non-user witnesses and keeps the user rows',
      () async {
        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: const [
            WitnessWeight(
              witnessUserId: _nonUserNode,
              m: 0.6,
              admitted: false,
            ),
            WitnessWeight(
              witnessUserId: 'Ucapnup01',
              m: 0.4,
              admitted: true,
            ),
          ],
        );

        final cached = await repo.cachedWindow(
          egoId: _ego,
          normalizedContext: _ctx,
        );
        expect(cached.map((w) => w.witnessUserId), ['Ucapnup01']);
        expect(cached.single.m, closeTo(0.4, 1e-9));
        expect(cached.single.admitted, isTrue);
      },
      skip: skipReason,
    );

    test(
      'storeWindow with only non-user witnesses leaves an empty window',
      () async {
        await repo.storeWindow(
          egoId: _ego,
          normalizedContext: _ctx,
          weights: const [
            WitnessWeight(
              witnessUserId: _nonUserNode,
              m: 1,
              admitted: false,
            ),
          ],
        );

        expect(
          await repo.cachedWindow(egoId: _ego, normalizedContext: _ctx),
          isEmpty,
        );
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
  for (final id in [..._userPeers, _nonUserNode]) {
    await _clearMrEdge(db, _ego, id);
    await _clearMrEdge(db, id, _ego);
  }
  final idList = _allUserIds.map((id) => "'$id'").join(', ');
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
  'UPDATE public.mr_publish_epoch SET epoch = 0 WHERE id = true',
);
