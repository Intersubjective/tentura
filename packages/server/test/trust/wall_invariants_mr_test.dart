@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';

/// B4: wall invariants against a live MeritRank (`docs/plans/
/// episode-closure-implementation-steps.md` § B4).
///
/// * A wall never raises the walled user's score for the wall's owner.
/// * Locality (unrelated frames move by at most ε) holds for wall add /
///   level change / remove while the owner's positive outgoing edges are
///   unchanged.
/// * Positive <-> wall sign transitions are exempt from locality
///   (`NEGATIVE_EDGES_FEATURE.md:263,351`) and are asserted separately.
/// * Removing a wall restores the previous scores within ε after `mr_sync`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WALL_INVARIANTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_wall_inv',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  // owner, walled user, relay, relay sibling, second branch, its leaf.
  const owner = 'Ub4wallowner01';
  const walled = 'Ub4wallwalled1';
  const relay = 'Ub4wallrelay01';
  const sibling = 'Ub4wallsibling';
  const other = 'Ub4wallother01';
  const leaf = 'Ub4wallleaf001';
  const ids = [owner, walled, relay, sibling, other, leaf];
  final idList = ids.map((i) => "'$i'").join(', ');

  /// Unrelated frames: neither the walled user nor its only ancestor
  /// (`relay`, whose mass legitimately flows into the wall) is observed.
  const frames = <(String, String)>[
    (owner, sibling),
    (owner, other),
    (owner, leaf),
    (other, leaf),
    (relay, sibling),
    (relay, leaf),
    // The relay's own view of the walled user is not the owner's wall.
    (relay, walled),
  ];

  /// Everything a removed wall must restore: the unrelated frames plus the
  /// owner's score of the walled user and of its ancestor `relay`.
  const restoreFrames = <(String, String)>[
    ...frames,
    (owner, walled),
    (owner, relay),
  ];

  late Connection writer;
  late TenturaDb db;
  late UserBlockRepository blockRepo;
  late TrustPublishRepository publishRepo;
  late TrustLedgerRepository ledger;
  var eps = 0.1;

  Future<void> project() => ledger.project([(owner, walled)]);

  Future<void> drain() async {
    await db.customStatement(
      'UPDATE public.trust_publisher_lease SET owner = NULL, '
      "lease_until = 'epoch' WHERE id = 1",
    );
    final token = await publishRepo.acquireLease('b4-test');
    expect(token, isNotNull);
    final rows = await publishRepo.readBatch(100);
    for (final row in rows) {
      await publishRepo.publish(row);
    }
    await publishRepo.sync();
    await publishRepo.ack(token!, rows);
  }

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

  Future<double> mrScore(String viewer, String other) async =>
      (await db
              .customSelect(
                r"SELECT score_value_of_dst::float8 AS s FROM mr_node_score($1, $2, '')",
                variables: [Variable<String>(viewer), Variable<String>(other)],
              )
              .getSingle())
          .read<double>('s');

  Future<Map<(String, String), double>> snapshot([
    List<(String, String)> fs = frames,
  ]) async => {for (final f in fs) f: await mrScore(f.$1, f.$2)};

  void expectLocal(
    Map<(String, String), double> before,
    Map<(String, String), double> after,
    String what, [
    List<(String, String)> fs = frames,
  ]) {
    for (final f in fs) {
      expect(
        after[f],
        closeTo(before[f]!, eps),
        reason: '$what: frame ${f.$1} -> ${f.$2} must stay within ε=$eps',
      );
    }
  }

  /// The owner's positive outgoing edges, in MR and in the projection table.
  /// Locality is only meaningful while these stay untouched.
  Future<Map<String, double?>> ownerPositiveEdges() async {
    final out = <String, double?>{};
    for (final o in [relay, other]) {
      out['mr:$o'] = await mrEdge(owner, o);
      final r = await db
          .customSelect(
            'SELECT target_w FROM public.user_trust_edge '
            "WHERE subject = '$owner' AND object = '$o'",
          )
          .getSingleOrNull();
      out['target:$o'] = r?.read<double>('target_w');
    }
    return out;
  }

  Future<void> expectPositiveEdgesUnchanged(
    Map<String, double?> base,
    String what,
  ) async {
    final now = await ownerPositiveEdges();
    expect(base.values.every((v) => v != null && v > 0), isTrue);
    expect(now, base, reason: '$what: owner positive edges must not change');
  }

  Future<void> vote(String s, String o) => db.customStatement(
    'INSERT INTO public.vote_user (subject, object, amount) '
    "VALUES ('$s', '$o', 1)",
  );

  /// Sets the owner's noisy-contact evidence for the walled user to [n]
  /// observations (levels: 3 -> 0.1, 6 -> 0.3, 10 -> 0.6).
  Future<void> setNoisy(int n) async {
    await db.customStatement(
      'DELETE FROM public.trust_evidence '
      "WHERE subject_user_id = '$owner' AND object_user_id = '$walled' "
      'AND kind = 7',
    );
    if (n > 0) {
      await db.customStatement('''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key, occurred_at)
VALUES ('Tb4noisy$n', '$owner', '$walled', 7, $n, 'b4:noisy:$n', now())
''');
    }
    await project();
    await drain();
  }

  Future<void> seedGraph() async {
    // The owner's positive outgoing edges; never touched by the tests.
    await vote(owner, relay);
    await vote(owner, other);
    await vote(relay, walled);
    await vote(relay, sibling);
    await vote(other, leaf);
    await vote(relay, leaf);
    await ledger.project([
      (owner, relay),
      (owner, other),
      (relay, walled),
      (relay, sibling),
      (other, leaf),
      (relay, leaf),
    ]);
    await drain();
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
      // m0209 ships the noisy wall off; these invariants use noisy walls.
      await writer.execute(
        "UPDATE public.trust_config SET value = 'true' "
        "WHERE key = 'noisy_wall_enabled'",
      );
      db = TenturaDb(target.databaseEnv);
      blockRepo = UserBlockRepository(target.databaseEnv, db);
      publishRepo = TrustPublishRepository(db);
      ledger = TrustLedgerRepository(db);
      for (var i = 0; i < ids.length; i++) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('${ids[i]}', '${ids[i]}', '${pgTestPublicKey('b4wall', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
      await db.customStatement(
        "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
      );
      final e = await db
          .customSelect(
            'SELECT (value)::text::float8 AS e FROM public.trust_config '
            "WHERE key = 'epsilon'",
          )
          .getSingleOrNull();
      eps = e?.read<double>('e') ?? eps;
    });

    setUp(seedGraph);

    tearDown(() async {
      await db.customStatement(
        'DELETE FROM public.user_block WHERE blocker_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.user_block_intent WHERE blocker_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.trust_evidence '
        'WHERE subject_user_id IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.vote_user WHERE subject IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.user_trust_edge WHERE subject IN ($idList)',
      );
      await db.customStatement(
        'DELETE FROM public.trust_publish_queue '
        'WHERE subject_user_id IN ($idList)',
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
    'fixture: the walled user is reachable before any wall',
    () async {
      expect(await mrScore(owner, walled), greaterThan(0));
    },
    skip: skipReason,
  );

  group('a wall never raises the walled score for its owner', () {
    test(
      'ban wall (-1)',
      () async {
        final before = await mrScore(owner, walled);
        await blockRepo.block(
          blockerId: owner,
          blockedId: walled,
          cascadeMode: 0,
        );
        await project();
        await drain();
        expect(await mrEdge(owner, walled), closeTo(-1, 1e-9));
        expect(await mrScore(owner, walled), lessThanOrEqualTo(before + 1e-9));
      },
      skip: skipReason,
    );

    for (final (n, level) in [(3, 0.1), (6, 0.3), (10, 0.6)]) {
      test(
        'noisy wall level $level (n=$n)',
        () async {
          final before = await mrScore(owner, walled);
          await setNoisy(n);
          expect(await mrEdge(owner, walled), closeTo(-level, 1e-9));
          expect(
            await mrScore(owner, walled),
            lessThanOrEqualTo(before + 1e-9),
          );
        },
        skip: skipReason,
      );
    }

    test(
      'a deeper wall level never scores above a shallower one',
      () async {
        await setNoisy(3);
        final shallow = await mrScore(owner, walled);
        await setNoisy(10);
        final deep = await mrScore(owner, walled);
        expect(deep, lessThanOrEqualTo(shallow + 1e-9));
      },
      skip: skipReason,
    );
  });

  group('wall level change bypasses ε (B1 step 2)', () {
    test(
      'level 0.1 -> 0.3 is published although |Δ| <= ε',
      () async {
        await db.customStatement(
          'UPDATE public.trust_config SET value = to_jsonb(0.5::float8) '
          "WHERE key = 'epsilon'",
        );
        addTearDown(
          () => db.customStatement(
            'UPDATE public.trust_config SET value = to_jsonb($eps::float8) '
            "WHERE key = 'epsilon'",
          ),
        );
        await setNoisy(3);
        expect(await mrEdge(owner, walled), closeTo(-0.1, 1e-9));

        await setNoisy(6);

        expect(
          await mrEdge(owner, walled),
          closeTo(-0.3, 1e-9),
          reason: 'a changed wall level must reach MR even within ε',
        );
      },
      skip: skipReason,
    );
  });

  group('locality (owner positive edges unchanged)', () {
    test(
      'wall add / level change / remove keep unrelated frames within ε '
      '(each step against the immediately preceding snapshot)',
      () async {
        var prev = await snapshot();
        final edges = await ownerPositiveEdges();

        await setNoisy(3);
        await expectPositiveEdgesUnchanged(edges, 'wall add');
        var next = await snapshot();
        expectLocal(prev, next, 'wall add (level 0.1)');
        prev = next;

        await setNoisy(6);
        await expectPositiveEdgesUnchanged(edges, 'level change 0.1->0.3');
        next = await snapshot();
        expectLocal(prev, next, 'level change (0.1 -> 0.3)');
        prev = next;

        await setNoisy(10);
        await expectPositiveEdgesUnchanged(edges, 'level change 0.3->0.6');
        next = await snapshot();
        expectLocal(prev, next, 'level change (0.3 -> 0.6)');
        prev = next;

        await setNoisy(0);
        await expectPositiveEdgesUnchanged(edges, 'wall remove');
        expectLocal(prev, await snapshot(), 'wall remove');
      },
      skip: skipReason,
    );

    // A ban wall has the single level -1, so "level change" applies to the
    // noisy walls only; ban add and remove are the supported transitions.
    test(
      'ban wall add and remove keep unrelated frames within ε',
      () async {
        final base = await snapshot();
        final edges = await ownerPositiveEdges();

        await blockRepo.block(
          blockerId: owner,
          blockedId: walled,
          cascadeMode: 0,
        );
        await project();
        await drain();
        await expectPositiveEdgesUnchanged(edges, 'ban add');
        expectLocal(base, await snapshot(), 'ban add');

        await blockRepo.unblock(blockerId: owner, blockedId: walled);
        await project();
        await drain();
        await expectPositiveEdgesUnchanged(edges, 'ban remove');
        expectLocal(base, await snapshot(), 'ban remove');
      },
      skip: skipReason,
    );
  });

  group('sign transitions (no locality assertion)', () {
    test(
      'positive -> ban wall -> positive republishes across the sign change',
      () async {
        await vote(owner, walled);
        await project();
        await drain();
        expect(await mrEdge(owner, walled), closeTo(0.5, 1e-9));
        final positive = await mrScore(owner, walled);

        await blockRepo.block(
          blockerId: owner,
          blockedId: walled,
          cascadeMode: 0,
        );
        await project();
        await drain();
        expect(await mrEdge(owner, walled), closeTo(-1, 1e-9));
        expect(
          await mrScore(owner, walled),
          lessThanOrEqualTo(positive + 1e-9),
        );

        await blockRepo.unblock(blockerId: owner, blockedId: walled);
        await project();
        await drain();
        expect(await mrEdge(owner, walled), closeTo(0.5, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'positive -> noisy wall flips the MR edge sign',
      () async {
        // Old positive evidence: trust_w > 0 but trust_recent < 0.05, which
        // is the precondition for a noisy wall to replace it.
        await db.customStatement('''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key, occurred_at)
VALUES ('Tb4oldpos001', '$owner', '$walled', 2, 1, 'b4:oldpos',
        now() - interval '400 days')
''');
        await project();
        await drain();
        final fold = await db
            .customSelect(
              'SELECT trust_w, trust_recent FROM public.trust_fold_pair( '
              "'$owner', '$walled')",
            )
            .getSingle();
        expect(fold.read<double>('trust_w'), greaterThan(0));
        expect(fold.read<double>('trust_recent'), lessThan(0.05));
        final positiveEdge = await mrEdge(owner, walled);
        expect(positiveEdge, isNotNull);
        expect(positiveEdge, greaterThan(0));
        final positive = await mrScore(owner, walled);
        expect(positive, greaterThan(0));

        await setNoisy(10);

        expect(await mrEdge(owner, walled), closeTo(-0.6, 1e-9));
        expect(
          await mrScore(owner, walled),
          lessThanOrEqualTo(positive + 1e-9),
        );
      },
      skip: skipReason,
    );

    test(
      'wall -> positive evidence flips the MR edge sign',
      () async {
        await setNoisy(3);
        expect(await mrEdge(owner, walled), lessThan(0));

        await setNoisy(0);
        await vote(owner, walled);
        await project();
        await drain();
        expect(await mrEdge(owner, walled), greaterThan(0));
      },
      skip: skipReason,
    );
  });

  group('wall removal restores previous scores within ε', () {
    test(
      'noisy wall removed',
      () async {
        final base = await snapshot(restoreFrames);

        await setNoisy(10);
        await setNoisy(0);

        expect(await mrEdge(owner, walled), isNull);
        expectLocal(
          base,
          await snapshot(restoreFrames),
          'restored',
          restoreFrames,
        );
      },
      skip: skipReason,
    );

    test(
      'ban wall removed',
      () async {
        final base = await snapshot(restoreFrames);

        await blockRepo.block(
          blockerId: owner,
          blockedId: walled,
          cascadeMode: 0,
        );
        await project();
        await drain();
        await blockRepo.unblock(blockerId: owner, blockedId: walled);
        await project();
        await drain();

        expect(await mrEdge(owner, walled), isNull);
        expectLocal(
          base,
          await snapshot(restoreFrames),
          'restored',
          restoreFrames,
        );
      },
      skip: skipReason,
    );
  });
}
