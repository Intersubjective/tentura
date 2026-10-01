@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_cutover_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/use_case/trust_cutover_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// B1: a block is a wall — `trust_project_pair` projects target -1 even
/// without evidence, and the bootstrap projects pre-existing blocks.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BAN_WALL_TEST_DB',
    defaultNamePrefix: 'tentura_test_ban_wall',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  const a = 'Ub1wallalice1';
  const b = 'Ub1wallbob001';
  const ids = [a, b, 'Ub1wallcarol01'];

  late Connection writer;
  late TenturaDb db;
  late UserBlockRepository blockRepo;
  late TrustPublishRepository publishRepo;
  late TrustLedgerRepository ledger;
  const c = 'Ub1wallcarol01';

  Future<Map<String, Object?>?> edge() async {
    final r = await db
        .customSelect(
          'SELECT target_w, prev_sent_weight FROM public.user_trust_edge '
          "WHERE subject = '$a' AND object = '$b'",
        )
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'target_w': r.read<double>('target_w'),
      'prev': r.read<double>('prev_sent_weight'),
    };
  }

  Future<int> queued() async =>
      (await db
              .customSelect(
                'SELECT count(*)::int AS c FROM public.trust_publish_queue '
                "WHERE subject_user_id = '$a' AND object_user_id = '$b'",
              )
              .getSingle())
          .read<int>('c');

  /// Projection through the production ledger port. Production wiring of
  /// block/unblock -> project is asserted in
  /// user_block_case_trust_projection_test.dart (UserBlockCase level).
  Future<void> project() => ledger.project([(a, b)]);

  /// Publishes everything queued to MeritRank, as the publisher worker does.
  Future<void> drain() async {
    await db.customStatement(
      'UPDATE public.trust_publisher_lease SET owner = NULL, '
      "lease_until = 'epoch' WHERE id = 1",
    );
    final token = await publishRepo.acquireLease('b1-test');
    expect(token, isNotNull);
    final rows = await publishRepo.readBatch(100);
    for (final row in rows) {
      await publishRepo.publish(row);
    }
    await publishRepo.sync();
    await publishRepo.ack(token!, rows);
  }

  /// Weight of the directed MR edge [s] -> [o], null when absent.
  Future<double?> mrEdge(String s, String o) async {
    final r = await db
        .customSelect(
          'SELECT e.weight::float8 AS w FROM mr_edgelist() e '
          r'WHERE e.src = $1 AND e.dst = $2',
          variables: [Variable<String>(s), Variable<String>(o)],
        )
        .getSingleOrNull();
    return r?.read<double>('w');
  }

  /// [viewer]'s score of [other] (cluster score of the destination).
  Future<double> mrScore(String viewer, String other) async =>
      (await db
              .customSelect(
                r"SELECT score_value_of_dst::float8 AS s FROM mr_node_score($1, $2, '')",
                variables: [Variable<String>(viewer), Variable<String>(other)],
              )
              .getSingle())
          .read<double>('s');

  Future<void> vote(String s, String o) => db.customStatement(
    'INSERT INTO public.vote_user (subject, object, amount) '
    "VALUES ('$s', '$o', 1)",
  );

  Future<String> cutoverStateText() async =>
      (await db
              .customSelect(
                "SELECT coalesce(string_agg(to_jsonb(s)::text, ' '), '') AS t "
                'FROM public.trust_cutover_state s',
              )
              .getSingle())
          .read<String>('t');

  TrustCutoverCase cutoverCase() => TrustCutoverCase(
    TrustCutoverRepository(db),
    MutatingUnitOfWork(db),
    env: Env(
      environment: Environment.test,
      publicOrigin: 'https://t.example',
      unsubscribeSigningSecret: 'secret',
    ),
    logger: Logger('test'),
    retryDelay: const Duration(milliseconds: 50),
  );

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
      db = TenturaDb(target.databaseEnv);
      blockRepo = UserBlockRepository(target.databaseEnv, db);
      publishRepo = TrustPublishRepository(db);
      ledger = TrustLedgerRepository(db);
      // Schema-agnostic snapshot of the post-migration cutover state, so
      // cutover tests (which may add ban_walls step rows/versions) are
      // isolated from each other.
      await db.customStatement(
        'CREATE TABLE public.b1_cutover_snap AS '
        'SELECT * FROM public.trust_cutover_state',
      );
      for (var i = 0; i < ids.length; i++) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('${ids[i]}', '${ids[i]}', '${pgTestPublicKey('b1wall', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    setUp(() async {
      await db.customStatement(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
    });

    tearDown(() async {
      await db.customStatement('DELETE FROM public.trust_cutover_state');
      await db.customStatement(
        'INSERT INTO public.trust_cutover_state '
        'SELECT * FROM public.b1_cutover_snap',
      );
      for (final table in ['user_block_intent', 'user_block']) {
        await db.customStatement(
          "DELETE FROM public.$table WHERE blocker_id IN ('$a', '$b')",
        );
      }
      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject IN ('$a', '$b')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge WHERE subject IN ('$a', '$b')",
      );
      await db.customStatement(
        'DELETE FROM public.trust_publish_queue '
        "WHERE subject_user_id IN ('$a', '$b')",
      );
      await db.customStatement('SELECT mr_reset()');
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'wall_publish_enabled is true after migrations',
    () async {
      final r = await db
          .customSelect(
            'SELECT (value = to_jsonb(true)) AS v '
            'FROM public.trust_config '
            "WHERE key = 'wall_publish_enabled'",
          )
          .getSingle();
      expect(r.read<bool>('v'), isTrue);
    },
    skip: skipReason,
  );

  test(
    'block without evidence: -1 edge row, queued, and published to MR',
    () async {
      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await project();

      final e = await edge();
      expect(e, isNotNull, reason: 'wall creates the user_trust_edge row');
      expect(e!['target_w'], closeTo(-1, 1e-9));
      expect(await queued(), 1);

      await drain();

      expect(await mrEdge(a, b), closeTo(-1, 1e-9));
      expect((await edge())!['prev'], closeTo(-1, 1e-9));
      expect(await queued(), 0);
    },
    skip: skipReason,
  );

  test(
    'sign change bypasses epsilon: MR goes 0.5 -> -1 after block',
    () async {
      await vote(a, b);
      await project();
      await drain();
      expect(await mrEdge(a, b), closeTo(0.5, 1e-9));

      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await project();
      expect(await queued(), 1);
      await drain();

      expect(await mrEdge(a, b), closeTo(-1, 1e-9));
    },
    skip: skipReason,
  );

  test(
    'unblock restores the fold value in MR (vote 0.5)',
    () async {
      await vote(a, b);
      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await project();
      await drain();
      expect(await mrEdge(a, b), closeTo(-1, 1e-9));

      await blockRepo.unblock(blockerId: a, blockedId: b);
      await project();
      expect((await edge())!['target_w'], closeTo(0.5, 1e-9));
      await drain();

      expect(await mrEdge(a, b), closeTo(0.5, 1e-9));
    },
    skip: skipReason,
  );

  test(
    'unblock without evidence removes the MR edge',
    () async {
      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await project();
      await drain();
      expect(await mrEdge(a, b), closeTo(-1, 1e-9));

      await blockRepo.unblock(blockerId: a, blockedId: b);
      await project();
      await drain();

      expect(await mrEdge(a, b), isNull);
      expect(await edge(), isNull);
    },
    skip: skipReason,
  );

  test(
    'wall behaviour: -1 ban edge collapses the blocked user score to 0 for '
    'the blocker while a sibling on the same path keeps its score',
    () async {
      const d = 'Ub1walldave001';
      await db.customStatement(
        'INSERT INTO public."user" (id, display_name, public_key, '
        'created_at, updated_at) '
        "VALUES ('$d', '$d', '${pgTestPublicKey('b1wall', 9)}', now(), now())",
      );
      addTearDown(
        () => db.customStatement(
          "DELETE FROM public.vote_user WHERE subject IN ('$d')",
        ),
      );
      await vote(a, c);
      await vote(c, b);
      await vote(c, d);
      await ledger.project([(a, c), (c, b), (c, d)]);
      await drain();
      final beforeB = await mrScore(a, b);
      final beforeD = await mrScore(a, d);
      expect(beforeB, greaterThan(0), reason: 'reachable through c');

      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await project();
      await drain();

      expect(await mrEdge(a, b), closeTo(-1, 1e-9));
      expect(
        await mrScore(a, b),
        closeTo(0, 1e-9),
        reason: 'absorbing wall: score collapses from $beforeB to 0',
      );
      expect(
        await mrScore(a, d),
        closeTo(beforeD, 1e-9),
        reason: 'sibling reachable through the same path is unaffected',
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge WHERE subject IN ('$c', '$d')",
      );
      await db.customStatement('DELETE FROM public."user" WHERE id = \'$d\'');
    },
    skip: skipReason,
  );

  test(
    'ban_walls step runs although the vote cutover is already done; '
    'existing blocks reach MR as -1 and the step is recorded',
    () async {
      // setUp left the vote cutover 'done'. A block that predates B1:
      await db.customStatement(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$a', '$b', '$b')",
      );
      expect(await edge(), isNull);

      await cutoverCase().runIfPending();
      await drain();

      final e = await edge();
      expect(e, isNotNull, reason: 'existing block bootstrapped');
      expect(e!['target_w'], closeTo(-1, 1e-9));
      expect(await mrEdge(a, b), closeTo(-1, 1e-9));
      expect(await cutoverStateText(), contains('ban_walls'));

      // Versioned state: a second run does not project the pair again.
      await db.customStatement(
        'DELETE FROM public.user_trust_edge '
        "WHERE subject = '$a' AND object = '$b'",
      );
      await cutoverCase().runIfPending();
      expect(await edge(), isNull, reason: 'ban_walls must not repeat');
    },
    skip: skipReason,
  );

  test(
    'fresh cutover (vote step pending) also bootstraps existing blocks',
    () async {
      await db.customStatement(
        "UPDATE public.trust_cutover_state SET status = 'pending', "
        "owner = NULL, lease_until = 'epoch' WHERE id = 1",
      );
      await db.customStatement(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        "VALUES ('$a', '$b', '$b')",
      );

      await cutoverCase().runIfPending();
      await drain();

      expect((await edge())!['target_w'], closeTo(-1, 1e-9));
      expect(await mrEdge(a, b), closeTo(-1, 1e-9));
    },
    skip: skipReason,
  );
}
