@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/trust_maintenance_sweep_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/user_trust_edge_repository.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/domain/use_case/trust_maintenance_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// A5: vote, block and maintenance callers project through
/// `trust_project_pair` (ledger fold) instead of writing evidence or
/// rebuilding effective edges.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_CALLERS_LEDGER_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_callers',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late UserTrustEdgeRepository voteRepo;
  late UserBlockRepository blockRepo;
  late TrustPublishRepository publishRepo;
  late UserRepository userRepo;
  late TrustMaintenanceCase maintenance;

  const a = 'Ua5callalice1';
  const b = 'Ua5callbob001';
  const ids = [a, b];

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

  Future<int> queued() async {
    final r = await db
        .customSelect(
          'SELECT count(*)::int AS c FROM public.trust_publish_queue '
          "WHERE subject_user_id = '$a' AND object_user_id = '$b'",
        )
        .getSingle();
    return r.read<int>('c');
  }

  Future<int> evidenceRows() async {
    final r = await db
        .customSelect(
          'SELECT count(*)::int AS c FROM public.trust_evidence '
          "WHERE subject_user_id = '$a' AND object_user_id = '$b'",
        )
        .getSingle();
    return r.read<int>('c');
  }

  /// `trust_project_pair` calls in call order (see [installCallLog]).
  Future<List<String>> calls() async {
    final r = await db
        .customSelect('SELECT s, o FROM public.a5_call_log ORDER BY seq')
        .get();
    return [
      for (final row in r) '${row.read<String>('s')}>${row.read<String>('o')}',
    ];
  }

  Future<void> resetCalls() =>
      db.customStatement('TRUNCATE public.a5_call_log');

  Future<BigInt> epoch() async {
    final r = await db
        .customSelect('SELECT epoch FROM public.mr_publish_epoch')
        .getSingle();
    return r.read<BigInt>('epoch');
  }

  Future<void> clearQueue() => db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    "WHERE subject_user_id = '$a' AND object_user_id = '$b'",
  );

  /// Pretends the publisher already sent the current target to MeritRank.
  Future<void> markPublished() async {
    await db.customStatement(
      'UPDATE public.user_trust_edge SET prev_sent_weight = target_w '
      "WHERE subject = '$a' AND object = '$b'",
    );
    await clearQueue();
  }

  Future<void> ack(double target) async {
    final token = await publishRepo.acquireLease('a5-test');
    expect(token, isNotNull);
    await publishRepo.ack(token!, [PublishRow(a, b, target)]);
  }

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
      voteRepo = UserTrustEdgeRepository(
        db,
        MeritrankRepository(db),
      );
      blockRepo = UserBlockRepository(target.databaseEnv, db);
      userRepo = UserRepository(
        target.databaseEnv,
        db,
        _NoopInviteGenealogyRepository(),
        InviteSeedPromptRepository(db),
      );
      publishRepo = TrustPublishRepository(db);
      maintenance = TrustMaintenanceCase(
        TrustMaintenanceSweepRepository(db),
        MeritrankRepository(db),
        env: Env(
          environment: Environment.test,
          trustSweepInterval: const Duration(hours: 1),
          trustSweepRetry: const Duration(minutes: 5),
        ),
        logger: Logger('TrustCallersLedgerTest'),
      );
      // Wrap trust_project_pair so every executed call is logged in order;
      // the original keeps running underneath.
      await db.customStatement(
        'CREATE TABLE public.a5_call_log '
        '(seq serial PRIMARY KEY, s text NOT NULL, o text NOT NULL)',
      );
      await db.customStatement(
        'ALTER FUNCTION public.trust_project_pair(text, text) '
        'RENAME TO trust_project_pair_orig',
      );
      await db.customStatement(r'''
CREATE FUNCTION public.trust_project_pair(p_subject text, p_object text)
    RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.a5_call_log (s, o) VALUES (p_subject, p_object);
  PERFORM public.trust_project_pair_orig(p_subject, p_object);
END;
$$
''');
      for (var i = 0; i < ids.length; i++) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('${ids[i]}', '${ids[i]}', '${pgTestPublicKey('a5call', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    setUp(() async {
      await resetCalls();
      await db.customStatement(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
      await db.customStatement(
        'UPDATE public.trust_publisher_lease SET owner = NULL, '
        "lease_until = 'epoch' WHERE id = 1",
      );
    });

    tearDown(() async {
      for (final table in [
        'user_block_intent',
        'user_block',
      ]) {
        await db.customStatement(
          "DELETE FROM public.$table WHERE blocker_id IN ('$a', '$b')",
        );
      }
      await db.customStatement(
        "DELETE FROM public.invitation WHERE id = 'Ia5callinv01'",
      );
      await db.customStatement(
        "DELETE FROM public.vote_user WHERE subject IN ('$a', '$b')",
      );
      await db.customStatement(
        "DELETE FROM public.trust_evidence WHERE subject_user_id IN ('$a', '$b')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge WHERE subject IN ('$a', '$b')",
      );
      await db.customStatement(
        "DELETE FROM public.\"user\" WHERE id LIKE 'a5bulk%'",
      );
      await db.customStatement(
        'DELETE FROM public.trust_publish_queue '
        "WHERE subject_user_id IN ('$a', '$b')",
      );
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  Future<void> vote(int amount) => voteRepo.setVoteAmountAndApplyEvidence(
    subjectUserId: a,
    objectUserId: b,
    newAmount: amount,
  );

  Future<void> insertHelpedEvidence() async {
    await db.customStatement(
      """
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key, occurred_at)
VALUES ('a5-ev-1', '$a', '$b', 2, 2, 'a5:ledger:1', now())
""",
    );
    await db
        .customSelect("SELECT public.trust_project_pair('$a', '$b')")
        .getSingle();
  }

  test(
    'vote up: projects the pair, target_w = 0.5, queue row, no evidence',
    () async {
      await vote(1);

      expect(await calls(), contains('$a>$b'));
      final e = await edge();
      expect(e, isNotNull);
      expect(e!['target_w'], closeTo(0.5, 1e-9));
      expect(await queued(), 1);
      expect(await evidenceRows(), 0);
    },
    skip: skipReason,
  );

  test(
    'vote removed after publication: projects, writes no evidence, keeps the '
    'zero-target row queued until ack',
    () async {
      await vote(1);
      await markPublished();
      expect((await edge())!['prev'], closeTo(0.5, 1e-9));
      await resetCalls();

      await vote(0);

      expect(await calls(), contains('$a>$b'));
      expect(await evidenceRows(), 0);
      final e = await edge();
      expect(e, isNotNull, reason: 'row kept until the zero is published');
      expect(e!['target_w'], 0);
      expect(e['prev'], closeTo(0.5, 1e-9));
      expect(await queued(), 1);

      await ack(0);

      expect(await edge(), isNull);
      expect(await queued(), 0);
    },
    skip: skipReason,
  );

  test(
    'block/unblock of a vote edge: queue transitions for the same pair',
    () async {
      await vote(1);
      await markPublished();
      expect(await queued(), 0);
      await resetCalls();

      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await blockRepo.applyWithdrawal(blockerId: a, blockedId: b);

      expect(await calls(), contains('$a>$b'));
      final blocked = await edge();
      expect(blocked, isNotNull);
      expect(blocked!['target_w'], closeTo(-1, 1e-9));
      expect(blocked['prev'], closeTo(0.5, 1e-9));
      expect(await queued(), 1);

      // Publisher delivers the ban wall (-1): row stays (nonzero target),
      // queue entry clears.
      await ack(-1);
      final walled = await edge();
      expect(walled, isNotNull);
      expect(walled!['target_w'], closeTo(-1, 1e-9));
      expect(walled['prev'], closeTo(-1, 1e-9));
      expect(await queued(), 0);
      await resetCalls();

      await blockRepo.unblock(blockerId: a, blockedId: b);

      expect(await calls(), contains('$a>$b'));
      final restored = await edge();
      expect(restored, isNotNull, reason: 'unblock re-projects without a row');
      expect(restored!['target_w'], closeTo(0.5, 1e-9));
      expect(await queued(), 1);
    },
    skip: skipReason,
  );

  test(
    'block/unblock of a ledger-evidence edge: fold value restored from '
    'retained evidence',
    () async {
      await insertHelpedEvidence();
      await markPublished();
      final fold = (await edge())!['target_w']! as double;
      expect(fold, greaterThan(0.5));
      await resetCalls();

      await blockRepo.block(blockerId: a, blockedId: b, cascadeMode: 0);
      await blockRepo.applyWithdrawal(blockerId: a, blockedId: b);

      expect(await calls(), contains('$a>$b'));
      expect((await edge())!['target_w'], closeTo(-1, 1e-9));
      expect(await queued(), 1);
      expect(await evidenceRows(), 1, reason: 'block never touches evidence');

      await ack(-1);
      await resetCalls();
      await blockRepo.unblock(blockerId: a, blockedId: b);

      expect(await calls(), contains('$a>$b'));
      expect((await edge())!['target_w'], closeTo(fold, 1e-9));
      expect(await queued(), 1);
      expect(await evidenceRows(), 1);
    },
    skip: skipReason,
  );

  test(
    'bindMutual keeps both vote_user rows, writes no evidence, projects both '
    'pairs in sorted order',
    () async {
      await db.customStatement(
        '''
INSERT INTO public.invitation (id, user_id, addressee_name, created_at, updated_at)
VALUES ('Ia5callinv01', '$a', 'Bob', now(), now())
''',
      );

      expect(
        await userRepo.bindMutual(invitationId: 'Ia5callinv01', userId: b),
        isTrue,
      );

      final votes = await db
          .customSelect(
            'SELECT subject, object, amount FROM public.vote_user '
            "WHERE subject IN ('$a', '$b') ORDER BY subject",
          )
          .get();
      expect(
        [
          for (final v in votes)
            '${v.read<String>('subject')}>${v.read<String>('object')}:${v.read<int>('amount')}',
        ],
        ['$a>$b:1', '$b>$a:1'],
      );
      final evidence = await db
          .customSelect(
            'SELECT count(*)::int AS c FROM public.trust_evidence '
            "WHERE subject_user_id IN ('$a', '$b')",
          )
          .getSingle();
      expect(evidence.read<int>('c'), 0);
      // Sorted by (subject, object): a < b, so a>b precedes b>a.
      expect(
        (await calls()).where((c) => c == '$a>$b' || c == '$b>$a').toList(),
        ['$a>$b', '$b>$a'],
      );
      final targets = await db
          .customSelect(
            'SELECT subject, target_w FROM public.user_trust_edge '
            "WHERE subject IN ('$a', '$b') ORDER BY subject",
          )
          .get();
      expect(targets.map((r) => r.read<double>('target_w')), [0.5, 0.5]);
      final q = await db
          .customSelect(
            'SELECT count(*)::int AS c FROM public.trust_publish_queue '
            "WHERE subject_user_id IN ('$a', '$b')",
          )
          .getSingle();
      expect(q.read<int>('c'), 2);
    },
    skip: skipReason,
  );

  test(
    'maintenance re-queues a pair whose decayed value moved by more than 0.1',
    () async {
      await insertHelpedEvidence();
      await markPublished();
      final before = (await edge())!['target_w']! as double;

      // One half-life of 'helped' (1 year) later the folded value decays.
      await db.customStatement(
        'UPDATE public.trust_evidence SET occurred_at = now() - interval '
        "'365 days' WHERE id = 'a5-ev-1'",
      );
      await maintenance.forceRefreshAll();

      final after = (await edge())!['target_w']! as double;
      expect(before - after, greaterThan(0.1));
      expect(await queued(), 1);
    },
    skip: skipReason,
  );

  test(
    'maintenance sweeps user_trust_edge only: an evidence-only pair is left '
    'alone',
    () async {
      await db.customStatement(
        """
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key, occurred_at)
VALUES ('a5-ev-2', '$a', '$b', 2, 2, 'a5:ledger:2', now())
""",
      );

      await maintenance.forceRefreshAll();

      expect(await calls(), isNot(contains('$a>$b')));
      expect(await edge(), isNull);
    },
    skip: skipReason,
  );

  test(
    'maintenance keyset sweep visits every edge pair once, in sorted order, '
    'across 200-row batches',
    () async {
      expect(
        Env(environment: Environment.test).trustSweepBatchSize,
        200,
      );
      const n = 450;
      await db.customStatement(
        """
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT 'a5bulk' || lpad(i::text, 4, '0'), 'bulk', 'pk-a5bulk-' || i, now(), now()
FROM generate_series(1, $n) AS i
""",
      );
      await db.customStatement(
        """
INSERT INTO public.user_trust_edge (subject, object, trust_w, wall_d, target_w)
SELECT '$a', 'a5bulk' || lpad(i::text, 4, '0'), 0.5, 0, 0.5
FROM generate_series(1, $n) AS i
""",
      );

      await maintenance.forceRefreshAll();

      final visited = (await calls()).where((c) => c.startsWith('$a>a5bulk'));
      expect(visited.toList(), [
        for (var i = 1; i <= n; i++) '$a>a5bulk${i.toString().padLeft(4, '0')}',
      ]);
    },
    skip: skipReason,
  );

  test(
    'runDue bumps the publish epoch once per sweep (24 h cadence)',
    () async {
      expect(
        Env(environment: Environment.test).trustSweepInterval,
        const Duration(hours: 24),
      );
      final daily = TrustMaintenanceCase(
        TrustMaintenanceSweepRepository(db),
        MeritrankRepository(db),
        env: Env(environment: Environment.test),
        logger: Logger('TrustCallersLedgerTest.daily'),
      );
      final before = await epoch();
      final now = DateTime.utc(2026, 3, 1, 12);

      await daily.runDue(now: now);
      final afterFirst = await epoch();
      expect(afterFirst, greaterThan(before));

      await daily.runDue(now: now.add(const Duration(hours: 23)));
      expect(await epoch(), afterFirst, reason: 'not due yet');
    },
    skip: skipReason,
  );
}

class _NoopInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
