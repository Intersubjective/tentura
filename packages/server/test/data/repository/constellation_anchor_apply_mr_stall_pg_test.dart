@Tags(['pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/meritrank_blackhole.dart';

/// Anchor writes remain independent of stalled or unavailable visibility RPCs.
/// The live connector blackhole probe is shared with the read-budget tests.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_APPLY_MR_STALL_TEST_DB',
    defaultNamePrefix: 'tentura_test_apply_mr_stall',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  const viewer = 'Ustallviewer0001';
  const peer = 'Ustallpeer000001';
  const params = (
    context: kConstellationContext,
    filters: ConstellationFieldMembershipFilters.defaults,
  );
  const budget = Duration(seconds: 5);
  final (blackhole, blackholeSkip) = await MeritRankBlackhole.probe();
  // The stall outlasts the budget by far, so only a cancel at the budget can
  // end it early.
  final stallSeconds = budget.inSeconds + 3;

  late DisposablePgWriterSession fixture;
  late Connection backend;
  late TenturaDb db;
  late ConstellationAnchorRepository repository;

  final ops = [
    AnchorApplyOp(
      clientOpId: 'pin-after-stall',
      kind: AnchorOpKind.upsert,
      target: ConstellationAnchorTarget.person(peer),
      position: const ConstellationAnchorPosition(
        xUnits: 2,
        yUnits: -3,
        coordinateSpaceVersion: 1,
      ),
      ifRevision: ConstellationAnchorRevision.zero,
    ),
  ];

  Future<AnchorApplyBatchResult> apply() => repository.applyBatch(
    viewerId: viewer,
    ops: ops,
  );

  Future<int> statementTimeoutMs() async {
    final row = await db.customSelect('''
SELECT (extract(epoch FROM current_setting('statement_timeout')::interval)
        * 1000)::bigint AS ms
''').getSingle();
    return row.read<int>('ms');
  }

  Future<int> visibilityComputations() async {
    final row = (await fixture.writer.execute(
      'SELECT CASE WHEN is_called THEN last_value ELSE 0 END '
      'FROM public.apply_mr_stall_entries',
    )).single;
    return (row.single! as num).toInt();
  }

  Future<void> expectRecorded() async {
    final logs = await fixture.writer.execute(
      'SELECT count(*) FROM public.constellation_anchor_op_log',
    );
    final anchors = await fixture.writer.execute(
      'SELECT count(*) FROM public.constellation_anchor',
    );
    expect(logs.single.single, 1, reason: 'The accepted op is logged once.');
    expect(anchors.single.single, 1, reason: 'The accepted anchor is stored.');
  }

  Future<int> backendPid() async =>
      (await db.customSelect('SELECT pg_backend_pid() AS pid').getSingle())
          .read<int>('pid');

  setUpAll(() async {
    fixture = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    db = TenturaDb.forTest(
      database: PgDatabase.opened(backend, enableMigrations: false),
    );
    repository = ConstellationAnchorRepository(
      db,
    );
    final writer = fixture.writer;
    // `sleep` blocks the visibility function, `fail` makes it raise at once
    // the way a connector error does; no row means it behaves normally.
    await writer.execute(
      'CREATE TABLE public.apply_mr_stall (mode text NOT NULL)',
    );
    // A sequence is not rolled back with the batch's transaction, so it counts
    // the visibility computations even of a batch that fails.
    await writer.execute('CREATE SEQUENCE public.apply_mr_stall_entries');
    await writer.execute('''
CREATE TABLE public.apply_mr_stall_seen_timeout (
  timeout_ms bigint NOT NULL
)
''');
    await writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO apply_mr_stall_visible_impl
''');
    await writer.execute('''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql VOLATILE AS \$probe\$
DECLARE
  _mode text := (SELECT mode FROM public.apply_mr_stall LIMIT 1);
BEGIN
  PERFORM nextval('public.apply_mr_stall_entries');
  INSERT INTO public.apply_mr_stall_seen_timeout
  VALUES ((extract(epoch FROM current_setting('statement_timeout')::interval)
           * 1000)::bigint);
  IF _mode = 'sleep' THEN
    PERFORM pg_sleep($stallSeconds);
  ELSIF _mode = 'fail' THEN
    RAISE EXCEPTION 'meritrank connector: call failed' USING ERRCODE = 'XX000';
  END IF;
  RETURN QUERY SELECT s.peer_id
  FROM public.apply_mr_stall_visible_impl(viewer_id, ctx) s;
END;
\$probe\$
''');
  });

  tearDownAll(() async {
    await db.close();
    if (backend.isOpen) await backend.close();
    await tearDownDisposablePgWriter(session: fixture);
  });

  setUp(() async {
    final writer = fixture.writer;
    await writer.execute('DELETE FROM public.apply_mr_stall');
    await writer.execute('DELETE FROM public.apply_mr_stall_seen_timeout');
    await writer.execute(
      "SELECT setval('public.apply_mr_stall_entries', 1, false)",
    );
    await writer.execute('DELETE FROM public.constellation_anchor_op_log');
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    for (final id in [viewer, peer]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$peer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$peer', '$viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    await writer.execute('SELECT public.mr_reset()');
    for (final (src, dst) in [(viewer, peer), (peer, viewer)]) {
      await writer.execute('''
SELECT public.mr_put_edge('$src', '$dst', 0.75::double precision, '${params.context}', 0)
''');
    }
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewer')
''');
  });

  group('applyBatch request budget', () {
    test(
      'runs with a statement_timeout equal to the apply request budget',
      () async {
        final connectionWide = await statementTimeoutMs();
        expect(
          connectionWide,
          isNot(budget.inMilliseconds),
          reason: 'The fixture connection must not already carry the budget.',
        );
        final result = await apply();
        expect(result.results.single.status, AnchorOpStatus.ok);

        expect(await visibilityComputations(), 0);
        final seen = await fixture.writer.execute(
          'SELECT DISTINCT timeout_ms FROM public.apply_mr_stall_seen_timeout',
        );
        expect(seen, isEmpty);
        final inTransaction = await db.withMutatingRepeatableRead(
          viewer,
          statementTimeoutMs,
        );
        expect(inTransaction, budget.inMilliseconds);
        expect(
          await statementTimeoutMs(),
          connectionWide,
          reason: 'The budget is transaction-local (SET LOCAL).',
        );
      },
    );

    Future<void> expectAckWithinBudget({
      required Future<void> Function() stall,
      required Future<void> Function() recover,
    }) async {
      final pidBefore = await backendPid();
      final attemptsBefore = await db.mrRpcAttempts();
      final clock = Stopwatch();
      late AnchorApplyBatchResult result;
      await stall();
      try {
        clock.start();
        result = await apply();
      } finally {
        clock.stop();
        await recover();
      }
      expect(result.results.single.status, AnchorOpStatus.ok);
      expect(result.results.single.replayed, isFalse);
      expect(result.results.single.anchor!.position, ops.single.position);
      expect(await visibilityComputations(), 0);
      expect(await db.mrRpcAttempts() - attemptsBefore, 0);
      expect(
        clock.elapsed,
        lessThanOrEqualTo(budget + const Duration(milliseconds: 100)),
      );
      await expectRecorded();
      expect(backend.isOpen, isTrue);
      expect(await backendPid(), pidBefore);
      final replayed = await apply();
      expect(replayed.results.single.status, AnchorOpStatus.ok);
      expect(replayed.results.single.replayed, isTrue);
      expect(replayed.results.single.anchor, result.results.single.anchor);
      expect(replayed.beforeRevision, result.afterRevision);
      expect(replayed.afterRevision, result.afterRevision);
    }

    test(
      'a blackholed MeritRank service leaves apply successful '
      'within the budget plus 100 ms and leaves the connection reusable',
      () async {
        final hole = blackhole!;
        addTearDown(hole.release);
        await expectAckWithinBudget(
          stall: hole.engage,
          recover: hole.release,
        );
      },
      skip: blackholeSkip,
      timeout: Timeout(budget * 3 + const Duration(seconds: 60)),
    );

    test(
      'a stalled visibility function leaves apply successful '
      'within budget and leaves the connection reusable',
      () async {
        await expectAckWithinBudget(
          stall: () => fixture.writer.execute(
            "INSERT INTO public.apply_mr_stall VALUES ('sleep')",
          ),
          recover: () =>
              fixture.writer.execute('DELETE FROM public.apply_mr_stall'),
        );
      },
      timeout: Timeout(budget * 3 + const Duration(seconds: 30)),
    );
  });

  group('applyBatch with a degraded MeritRank', () {
    test(
      'a failing visibility service leaves apply successful and replayable',
      () async {
        final before = await db.mrRpcAttempts();
        await fixture.writer.execute(
          "INSERT INTO public.apply_mr_stall VALUES ('fail')",
        );
        final result = await apply();
        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(result.results.single.replayed, isFalse);
        expect(await visibilityComputations(), 0);
        expect(await db.mrRpcAttempts() - before, 0);
        await expectRecorded();
        await fixture.writer.execute('DELETE FROM public.apply_mr_stall');
        final recovered = await apply();
        expect(recovered.results.single.status, AnchorOpStatus.ok);
        expect(recovered.results.single.replayed, isTrue);
        expect(recovered.afterRevision, result.afterRevision);
      },
    );

    test(
      'a non-visible peer can be pinned without consulting MeritRank',
      () async {
        await fixture.writer.execute('DELETE FROM public.vote_user');
        await fixture.writer.execute('SELECT public.mr_reset()');

        final result = await apply();

        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(result.results.single.reason, isNull);
        expect(await visibilityComputations(), 0);
        final logs = await fixture.writer.execute(
          'SELECT count(*) FROM public.constellation_anchor_op_log',
        );
        expect(logs.single.single, 1);
      },
    );
  });
}
