@Tags(['pg', 'mr'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart'
    show Connection, ServerException, Session;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

import '../../support/constellation_anchor_tombstone_fixture.dart';
import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

// The batch DTOs and methods are deliberately required at compile time. A
// missing batch API must make the acceptance command red even without Postgres.
// Scope: the implementation plan's U13 Tests explicitly names foreign-write
// retries, visibility changes/cascade deletes and MR-outage recovery. These are
// protocol correctness checks for the U11 transaction used by applyBatch.
// Preparation/query batching belongs to part 2; multi-tab contention, latency,
// RPC-count, EXPLAIN and WAL measurement gates belong to part 3.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_BATCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_cabatch',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const viewer = 'Ucabatchview01';
  const otherViewer = 'Ucabatchview02';
  const firstPeer = 'Ucabatchpeer01';
  const secondPeer = 'Ucabatchpeer02';
  const unavailablePeer = 'Ucabatchhide01';
  const openBeacon = 'Bcabatchopen01';
  const closedBeacon = 'Bcabatchclos01';
  const params = (
    context: kConstellationContext,
    filters: ConstellationFieldMembershipFilters.defaults,
  );
  late DisposablePgWriterSession session;
  late TenturaDb db;
  late ConstellationAnchorRepositoryPort repository;
  late ConstellationFieldRepository fields;

  ConstellationAnchorPosition position(double x, double y) =>
      ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: 1,
      );

  AnchorApplyOp upsert(
    String opId,
    ConstellationAnchorTarget target, {
    double x = 1,
    double y = -1,
    ConstellationAnchorRevision? ifRevision,
  }) => AnchorApplyOp(
    clientOpId: opId,
    kind: AnchorOpKind.upsert,
    target: target,
    position: position(x, y),
    ifRevision: ifRevision,
  );

  AnchorApplyOp delete(
    String opId,
    ConstellationAnchorTarget target, {
    ConstellationAnchorRevision? ifRevision,
  }) => AnchorApplyOp(
    clientOpId: opId,
    kind: AnchorOpKind.delete,
    target: target,
    ifRevision: ifRevision,
  );

  Future<AnchorApplyBatchResult> apply(
    List<AnchorApplyOp> ops, {
    String viewerId = viewer,
    ({String context, ConstellationFieldMembershipFilters filters})
        projectionParams =
        params,
  }) => repository.applyBatch(
    viewerId: viewerId,
    ops: ops,
  );

  Future<ConstellationAnchorProjection> freshAnchors({
    String viewerId = viewer,
    ({String context, ConstellationFieldMembershipFilters filters})
        projectionParams =
        params,
  }) async => (await fields.readSnapshot(
    viewerId: viewerId,
    context: projectionParams.context,
    params: (
      filters: projectionParams.filters,
      projection: ConstellationProjection.anchors,
    ),
  )).anchorProjection;

  Future<void> expectFreshProjection(
    AnchorApplyBatchResult result, {
    String viewerId = viewer,
    ({String context, ConstellationFieldMembershipFilters filters})
        projectionParams =
        params,
  }) async {
    for (final op in result.results) {
      if (op.anchor != null && !op.replayed) {
        expect(op.anchor!.revision, op.resultingTargetRevision);
        expect(op.anchor!.position, op.position);
      }
    }
    final anchors = await freshAnchors(
      viewerId: viewerId,
      projectionParams: projectionParams,
    );
    final full = await fields.readSnapshot(
      viewerId: viewerId,
      context: projectionParams.context,
      params: (
        filters: projectionParams.filters,
        projection: ConstellationProjection.full,
      ),
    );
    expect(anchors, full.anchorProjection);
    expect(
      anchors.revision.value,
      greaterThanOrEqualTo(result.afterRevision.value),
    );
  }

  Future<void> reciprocalTrust(String a, String b) => db.customStatement('''
INSERT INTO public.vote_user
  (subject, object, amount, created_at, updated_at)
VALUES
  ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  Future<List<Map<String, Object?>>> opLog() async {
    final rows = await session.writer.execute('''
SELECT client_op_id, result::text, revision::text
FROM public.constellation_anchor_op_log
WHERE viewer_id = '$viewer'
ORDER BY client_op_id
''');
    return [
      for (final row in rows)
        {
          'id': row[0],
          'result': jsonDecode(row[1]! as String),
          'revision': row[2],
        },
    ];
  }

  Future<Map<String, List<String>>> databaseState() async {
    final state = <String, List<String>>{};
    for (final (table, order) in [
      ('constellation_anchor', 'id'),
      ('constellation_anchor_cursor', 'viewer_id'),
      ('constellation_anchor_target_watermark', 'target_kind, target_id'),
      ('constellation_anchor_op_log', 'client_op_id'),
    ]) {
      final rows = await session.writer.execute('''
SELECT row_to_json(t)::text FROM public.$table t
WHERE viewer_id = '$viewer' ORDER BY $order
''');
      state[table] = [for (final row in rows) row.single! as String];
    }
    return state;
  }

  // Hold the real viewer row lock until the batch is observably waiting on
  // SELECT ... FOR UPDATE. A foreign mutation then changes the locked row in
  // the batch's first snapshot, forcing a whole-transaction RR retry.
  Future<
    ({
      AnchorApplyBatchResult result,
      DateTime blockedTransactionStartedAt,
      ConstellationAnchorRevision beforeReleaseRevision,
    })
  >
  applyWhileCursorLocked(
    List<AnchorApplyOp> ops, {
    required Future<void> Function(Session tx) foreignMutation,
  }) async {
    final blocker = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    Future<void>? completion;
    AnchorApplyBatchResult? batchResult;
    Object? batchError;
    StackTrace? batchStack;
    var completed = false;
    DateTime? blockedStartedAt;
    ConstellationAnchorRevision? beforeReleaseRevision;
    try {
      await blocker.runTx((tx) async {
        final pid =
            (await tx.execute('SELECT pg_backend_pid()')).single.single! as int;
        await tx.execute('''
SELECT set_config('tentura.mutating_user_id', '$viewer', true)
''');
        await tx.execute('''
SELECT revision FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer' FOR UPDATE
''');
        completion = apply(ops)
            .then<void>(
              (result) {
                batchResult = result;
              },
              onError: (Object error, StackTrace stack) {
                batchError = error;
                batchStack = stack;
              },
            )
            .whenComplete(() {
              completed = true;
            });
        blockedStartedAt = await _waitForCursorForUpdate(
          session.writer,
          blockerPid: pid,
          hasCompleted: () => completed,
        );
        await foreignMutation(tx);
        final revision =
            (await tx.execute('''
SELECT revision::text FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer'
''')).single.single!
                as String;
        beforeReleaseRevision = ConstellationAnchorRevision(
          BigInt.parse(revision),
        );
      });
      await completion!.timeout(kCompletionWait);
      if (batchError != null) {
        Error.throwWithStackTrace(batchError!, batchStack!);
      }
      return (
        result: batchResult!,
        blockedTransactionStartedAt: blockedStartedAt!,
        beforeReleaseRevision: beforeReleaseRevision!,
      );
    } finally {
      await blocker.close();
      // A failed assertion must also release and drain the pending batch.
      if (completion != null) await completion!.timeout(kCompletionWait);
    }
  }

  Future<void> expectRetriedWriteTransaction(
    String opId,
    DateTime firstAttemptStartedAt,
  ) async {
    final rows = await session.writer.execute('''
SELECT isolation_level, read_only, transaction_started_at
FROM anchor_batch_probe.write_context
WHERE client_op_id = '$opId'
''');
    expect(rows, hasLength(1));
    expect(rows.single[0], 'repeatable read');
    expect(rows.single[1], 'off');
    expect(
      (rows.single[2]! as DateTime).isAfter(firstAttemptStartedAt),
      isTrue,
      reason:
          'A new transaction must replace the snapshot that waited on the cursor.',
    );
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    await session.writer.execute('CREATE SCHEMA anchor_batch_probe');
    await session.writer.execute('''
CREATE TABLE anchor_batch_probe.write_context (
  client_op_id text NOT NULL,
  isolation_level text NOT NULL,
  read_only text NOT NULL,
  transaction_started_at timestamptz NOT NULL
)
''');
    await session.writer.execute(r'''
CREATE FUNCTION anchor_batch_probe.record_write_context()
RETURNS trigger LANGUAGE plpgsql AS $probe$
BEGIN
  INSERT INTO anchor_batch_probe.write_context
  VALUES (NEW.client_op_id, current_setting('transaction_isolation'),
    current_setting('transaction_read_only'), transaction_timestamp());
  RETURN NEW;
END;
$probe$
''');
    await session.writer.execute('''
CREATE TRIGGER anchor_batch_write_context_probe
AFTER INSERT ON public.constellation_anchor_op_log
FOR EACH ROW EXECUTE FUNCTION anchor_batch_probe.record_write_context()
''');
    await session.writer.execute('''
CREATE TABLE anchor_batch_probe.visibility_outage (active boolean NOT NULL)
''');
    // Install the service-boundary shim before any visibility query can cache
    // the original function OID. It delegates to real MR except in the outage
    // test, following the existing frozen-visibility fixture convention.
    await session.writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO anchor_batch_visible_peers_impl
''');
    await session.writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql STABLE AS $probe$
BEGIN
  IF EXISTS (SELECT 1 FROM anchor_batch_probe.visibility_outage WHERE active) THEN
    RAISE EXCEPTION USING ERRCODE = '08006', MESSAGE = 'simulated MeritRank outage';
  END IF;
  RETURN QUERY SELECT s.peer_id
  FROM public.anchor_batch_visible_peers_impl(viewer_id, ctx) s;
END;
$probe$
''');
    final profiles = _PgProfileLookup(db);
    repository = ConstellationAnchorRepository(
      db,
    );
    fields = ConstellationFieldRepository(db, profiles);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await session.writer.execute(
      'DELETE FROM anchor_batch_probe.visibility_outage',
    );
    await session.writer.execute(
      'DELETE FROM anchor_batch_probe.write_context',
    );
    await db.customStatement('DELETE FROM public.constellation_anchor');
    await db.customStatement('DELETE FROM public.constellation_anchor_cursor');
    await db.customStatement('DELETE FROM public.constellation_anchor_op_log');
    await db.customStatement(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await db.customStatement('DELETE FROM public.beacon');
    await db.customStatement('DELETE FROM public.user_block');
    await db.customStatement('DELETE FROM public.vote_user');
    await db.customStatement('DELETE FROM public."user"');
    for (final id in [
      viewer,
      otherViewer,
      firstPeer,
      secondPeer,
      unavailablePeer,
    ]) {
      await db.customStatement('''
INSERT INTO public."user"
  (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    for (final peer in [firstPeer, secondPeer, unavailablePeer]) {
      await reciprocalTrust(viewer, peer);
    }
    await reciprocalTrust(otherViewer, firstPeer);
    await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$unavailablePeer', '$unavailablePeer')
''');
    for (final (id, status) in [(openBeacon, 0), (closedBeacon, 5)]) {
      await db.customStatement('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   created_at, updated_at, published_at)
VALUES ('$id', '$firstPeer', '$id', 'batch projection fixture', $status,
  true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z')
''');
    }
    await db.customStatement('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, status, created_at, updated_at)
VALUES ('$closedBeacon', '$viewer', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
  });

  tearDown(() async {
    await db.customStatement('''
DROP TRIGGER IF EXISTS anchor_batch_rollback_probe
ON public.constellation_anchor_op_log
''');
    await db.customStatement(
      'DROP FUNCTION IF EXISTS public.anchor_batch_rollback_probe()',
    );
  });

  group('anchor batch idempotency', () {
    test(
      'replays an accepted operation before checking changed authorization',
      () async {
        final op = upsert(
          'accepted-before-block',
          ConstellationAnchorTarget.person(firstPeer),
        );
        final accepted = await apply([op]);
        expect(accepted.results.single.status, AnchorOpStatus.ok);
        await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$firstPeer', '$firstPeer')
''');
        final beforeReplay = await databaseState();
        final currentRevision = await repository.readWatermark(viewer);

        final replay = await apply([op]);

        expect(_resultValues(replay), _resultValues(accepted));
        expect(replay.beforeRevision, currentRevision);
        expect(replay.afterRevision, currentRevision);
        expect(await databaseState(), beforeReplay);
        expect((await freshAnchors()).pinnedPeers, isEmpty);
        await expectFreshProjection(replay);
      },
    );

    test(
      'replays the recorded placement after a later move without writing',
      () async {
        final peer = ConstellationAnchorTarget.person(firstPeer);
        final original = upsert('original-placement', peer);
        final first = await apply([original]);
        expect(first.results.single.status, AnchorOpStatus.ok);
        await apply([upsert('later-placement', peer, x: 2, y: 3)]);
        final beforeReplay = await databaseState();
        final current = await repository.readWatermark(viewer);

        final replay = await apply([original]);

        expect(replay.beforeRevision, current);
        expect(replay.afterRevision, current);
        expect(_resultValues(replay), _resultValues(first));
        expect(replay.results.single.position, position(1, -1));
        expect((await freshAnchors()).anchors.single.position, position(2, 3));
        expect(await databaseState(), beforeReplay);
        await expectFreshProjection(replay);
      },
    );

    test(
      'replays a missing-target rejection even after the target is created',
      () async {
        final op = upsert(
          'unavailable-placement',
          ConstellationAnchorTarget.person(unavailablePeer),
        );
        await db.customStatement(
          'DELETE FROM public."user" WHERE id = \'$unavailablePeer\'',
        );
        final rejected = await apply([op]);
        expect(rejected.results.single.status, AnchorOpStatus.rejected);
        expect(rejected.results.single.reason, 'target_not_found');
        expect(rejected.afterRevision, rejected.beforeRevision);
        await db.customStatement(
          'INSERT INTO public."user" (id, display_name, public_key) '
          "VALUES ('$unavailablePeer', '$unavailablePeer', "
          "'pk-$unavailablePeer')",
        );
        final beforeReplay = await databaseState();

        final replay = await apply([op]);

        expect(_resultValues(replay), _resultValues(rejected));
        expect(replay.afterRevision, rejected.afterRevision);
        expect(await databaseState(), beforeReplay);
        expect((await freshAnchors()).anchors, isEmpty);
        final newlyAuthorized = await apply([
          upsert('authorized-new-id', op.target),
        ]);
        expect(newlyAuthorized.results.single.status, AnchorOpStatus.ok);
      },
    );

    final changedPayloads = <String, AnchorApplyOp Function()>{
      'position': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(firstPeer),
        x: 2,
      ),
      'target': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(secondPeer),
      ),
      'target kind': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.beacon(firstPeer),
      ),
      'operation kind': () => delete(
        'payload-id',
        ConstellationAnchorTarget.person(firstPeer),
      ),
      'conditional revision': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(firstPeer),
        ifRevision: ConstellationAnchorRevision(BigInt.one),
      ),
    };
    for (final MapEntry(key: field, value: changedOp)
        in changedPayloads.entries) {
      test(
        'rejects reuse of an operation id with a different $field',
        () async {
          final first = await apply([
            upsert('payload-id', ConstellationAnchorTarget.person(firstPeer)),
          ]);
          final beforeReuse = await databaseState();

          final reused = await apply([changedOp()]);

          expect(reused.results.single.status, AnchorOpStatus.rejected);
          expect(reused.results.single.reason, 'op_id_reused');
          expect(reused.beforeRevision, first.afterRevision);
          expect(reused.afterRevision, first.afterRevision);
          expect(await databaseState(), beforeReuse);
          await expectFreshProjection(reused);
        },
      );
    }

    test('scopes operation ids to the viewer account', () async {
      final op = upsert(
        'shared-client-id',
        ConstellationAnchorTarget.person(firstPeer),
      );
      final first = await apply([op]);
      final second = await apply([op], viewerId: otherViewer);

      expect(first.results.single.status, AnchorOpStatus.ok);
      expect(second.results.single.status, AnchorOpStatus.ok);
      expect(second.beforeRevision, ConstellationAnchorRevision.zero);
      expect(second.afterRevision.value, BigInt.one);
      await expectFreshProjection(second, viewerId: otherViewer);
    });

    test(
      'stores bounded per-operation replay data without a projection',
      () async {
        final result = await apply([
          upsert('minimal-log', ConstellationAnchorTarget.person(firstPeer)),
        ]);
        final logged = (await opLog()).single;
        final payload = logged['result']! as Map<String, dynamic>;

        expect(logged['id'], 'minimal-log');
        expect(logged['revision'], result.afterRevision.toDecimalString());
        expect(payload['status'], 'OK');
        expect(payload.keys, isNot(contains('projection')));
        expect(payload.keys, isNot(contains('anchorProjection')));
        expect(payload.keys, isNot(contains('anchors')));
        expect(payload.keys, isNot(contains('pinnedPeers')));
        // U10's existing m0228 result-size constraint already applies to every
        // inserted row. U13's minimal replay result must fit that schema; the
        // migration's constraint/oversize cases remain covered by U10 tests.
        expect(utf8.encode(jsonEncode(payload)).length, lessThanOrEqualTo(257));
      },
    );
  });

  group('anchor batch conditional target revisions', () {
    test(
      'checks target existence before a mismatched conditional revision',
      () async {
        await db.customStatement(
          'DELETE FROM public."user" WHERE id = \'$unavailablePeer\'',
        );
        final before = await repository.readWatermark(viewer);
        final result = await apply([
          upsert(
            'unavailable-with-stale-revision',
            ConstellationAnchorTarget.person(unavailablePeer),
            ifRevision: ConstellationAnchorRevision(BigInt.from(99)),
          ),
        ]);

        expect(result.results.single.status, AnchorOpStatus.rejected);
        expect(result.results.single.reason, 'target_not_found');
        expect(result.beforeRevision, before);
        expect(result.afterRevision, before);
        expect((await freshAnchors()).anchors, isEmpty);
        final logged = (await opLog()).single;
        expect(logged['id'], 'unavailable-with-stale-revision');
        expect(
          (logged['result']! as Map<String, dynamic>)['reason'],
          'target_not_found',
        );
        await expectFreshProjection(result);
      },
    );

    test('rejects a stale target revision and records the conflict', () async {
      final peer = ConstellationAnchorTarget.person(firstPeer);
      final first = await apply([upsert('initial-placement', peer)]);
      final guarded = upsert(
        'stale-compensation',
        peer,
        x: 3,
        ifRevision: ConstellationAnchorRevision.zero,
      );
      final rejected = await apply([guarded]);

      expect(rejected.results.single.status, AnchorOpStatus.rejected);
      expect(rejected.results.single.reason, 'conflict');
      expect(rejected.afterRevision, first.afterRevision);
      expect((await freshAnchors()).anchors.single.position, position(1, -1));
      expect(
        (await opLog()).map((row) => row['id']),
        contains('stale-compensation'),
      );
      final beforeReplay = await databaseState();
      final replay = await apply([guarded]);
      expect(_resultValues(replay), _resultValues(rejected));
      expect(await databaseState(), beforeReplay);
    });

    test(
      'compares the target watermark instead of the account cursor',
      () async {
        final peer = ConstellationAnchorTarget.person(firstPeer);
        final first = await apply([upsert('first-peer', peer)]);
        final unrelated = await apply([
          upsert('second-peer', ConstellationAnchorTarget.person(secondPeer)),
        ]);
        expect(
          unrelated.afterRevision.value,
          greaterThan(first.afterRevision.value),
        );

        final compensated = await apply([
          upsert(
            'restore-first-peer',
            peer,
            x: 3,
            ifRevision: first.results.single.resultingTargetRevision,
          ),
        ]);

        expect(compensated.results.single.status, AnchorOpStatus.ok);
        expect(compensated.beforeRevision, unrelated.afterRevision);
        expect(
          compensated.afterRevision.value,
          unrelated.afterRevision.value + BigInt.one,
        );
        await expectFreshProjection(compensated);
      },
    );

    test(
      'retains the target watermark after deletion for guarded restoration',
      () async {
        final peer = ConstellationAnchorTarget.person(firstPeer);
        final placed = await apply([upsert('place-peer', peer)]);
        final removed = await apply([
          delete(
            'remove-peer',
            peer,
            ifRevision: placed.results.single.resultingTargetRevision,
          ),
        ]);
        expect(removed.results.single.status, AnchorOpStatus.ok);
        expect(
          removed.results.single.resultingTargetRevision,
          removed.afterRevision,
        );
        expect((await freshAnchors()).anchors, isEmpty);
        final watermark = await session.writer.execute('''
SELECT revision::text FROM public.constellation_anchor_target_watermark
WHERE viewer_id = '$viewer' AND target_kind = 'PERSON' AND target_id = '$firstPeer'
''');
        expect(
          watermark.single.single,
          removed.afterRevision.toDecimalString(),
        );
        final afterDelete = await databaseState();

        final staleRestore = await apply([
          upsert(
            'stale-restore',
            peer,
            ifRevision: placed.results.single.resultingTargetRevision,
          ),
        ]);
        expect(staleRestore.results.single.status, AnchorOpStatus.rejected);
        expect(staleRestore.results.single.reason, 'conflict');
        expect(staleRestore.afterRevision, removed.afterRevision);
        final replay = await apply([
          delete(
            'remove-peer',
            peer,
            ifRevision: placed.results.single.resultingTargetRevision,
          ),
        ]);
        expect(_resultValues(replay), _resultValues(removed));
        expect(replay.afterRevision, removed.afterRevision);
        final stateAfterReplay = await databaseState();
        expect(
          stateAfterReplay['constellation_anchor'],
          afterDelete['constellation_anchor'],
        );
        expect(
          stateAfterReplay['constellation_anchor_target_watermark'],
          afterDelete['constellation_anchor_target_watermark'],
        );

        final restored = await apply([
          upsert(
            'guarded-restore',
            peer,
            x: 2,
            ifRevision: removed.results.single.resultingTargetRevision,
          ),
        ]);
        expect(restored.results.single.status, AnchorOpStatus.ok);
        expect((await freshAnchors()).anchors.single.position, position(2, -1));
        await expectFreshProjection(restored);
      },
    );
  });

  group('anchor batch ordered settlement and atomicity', () {
    test('settles accepted and rejected operations in input order', () async {
      final seeded = await apply([
        upsert(
          'seed-second-peer',
          ConstellationAnchorTarget.person(secondPeer),
        ),
      ]);
      final result = await apply([
        upsert('accepted-person', ConstellationAnchorTarget.person(firstPeer)),
        upsert(
          'missing-person',
          ConstellationAnchorTarget.person('Ucabatchmiss01'),
          ifRevision: ConstellationAnchorRevision(BigInt.from(99)),
        ),
        upsert(
          'conflicting-person',
          ConstellationAnchorTarget.person(secondPeer),
          x: 3,
          ifRevision: ConstellationAnchorRevision.zero,
        ),
        upsert('accepted-beacon', ConstellationAnchorTarget.beacon(openBeacon)),
      ]);

      expect(result.results.map((r) => r.clientOpId), [
        'accepted-person',
        'missing-person',
        'conflicting-person',
        'accepted-beacon',
      ]);
      expect(result.results.map((r) => r.status), [
        AnchorOpStatus.ok,
        AnchorOpStatus.rejected,
        AnchorOpStatus.rejected,
        AnchorOpStatus.ok,
      ]);
      expect(result.results.map((r) => r.reason), [
        null,
        'target_not_found',
        'conflict',
        null,
      ]);
      expect(result.beforeRevision, seeded.afterRevision);
      expect(
        result.afterRevision.value,
        seeded.afterRevision.value + BigInt.from(2),
      );
      expect(
        result.results.first.resultingTargetRevision?.value,
        seeded.afterRevision.value + BigInt.one,
      );
      expect(result.results.last.resultingTargetRevision, result.afterRevision);
      expect((await freshAnchors()).anchors, hasLength(3));
      expect(await opLog(), hasLength(5));
      await expectFreshProjection(result);
    });

    test(
      'rolls back anchors, cursor, target watermarks and op log on a database error',
      () async {
        await apply([
          upsert(
            'existing-placement',
            ConstellationAnchorTarget.person(firstPeer),
          ),
        ]);
        final before = await databaseState();
        final beforeProjection = await freshAnchors();
        await db.customStatement(r'''
CREATE FUNCTION public.anchor_batch_rollback_probe()
RETURNS trigger LANGUAGE plpgsql AS $probe$
BEGIN
  IF NEW.client_op_id = 'rollback-fault' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'anchor_batch_rollback_probe';
  END IF;
  RETURN NEW;
END;
$probe$
''');
        await db.customStatement('''
CREATE TRIGGER anchor_batch_rollback_probe
BEFORE INSERT ON public.constellation_anchor_op_log
FOR EACH ROW EXECUTE FUNCTION public.anchor_batch_rollback_probe()
''');

        await expectLater(
          apply([
            upsert(
              'would-move-peer',
              ConstellationAnchorTarget.person(firstPeer),
              x: 3,
            ),
            upsert(
              'rollback-fault',
              ConstellationAnchorTarget.person(secondPeer),
            ),
          ]),
          throwsA(
            isA<ServerException>()
                .having((e) => e.code, 'SQLSTATE', 'P0001')
                .having(
                  (e) => e.message,
                  'probe',
                  'anchor_batch_rollback_probe',
                ),
          ),
        );

        expect(await databaseState(), before);
        expect(await freshAnchors(), beforeProjection);
      },
    );
  });

  group('anchor batch cursor locking and snapshot retries', () {
    test(
      'waits for the viewer cursor with FOR UPDATE before writing operations',
      () async {
        final seeded = await apply([
          upsert('seed-cursor', ConstellationAnchorTarget.person(firstPeer)),
        ]);
        final before = await databaseState();

        final run = await applyWhileCursorLocked(
          [
            upsert(
              'waiting-placement',
              ConstellationAnchorTarget.person(secondPeer),
            ),
          ],
          foreignMutation: (_) async {
            expect(await databaseState(), before);
          },
        );

        expect(run.result.results.single.status, AnchorOpStatus.ok);
        expect(run.result.beforeRevision, seeded.afterRevision);
        expect(
          run.result.afterRevision.value,
          seeded.afterRevision.value + BigInt.one,
        );
        await expectFreshProjection(run.result);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'retries a changed cursor snapshot and includes the concurrent anchor move',
      () async {
        final seeded = await apply([
          upsert(
            'seed-foreign-move',
            ConstellationAnchorTarget.person(firstPeer),
          ),
        ]);

        final run = await applyWhileCursorLocked(
          [
            upsert(
              'own-placement',
              ConstellationAnchorTarget.person(secondPeer),
              x: 2,
            ),
          ],
          foreignMutation: (tx) async {
            await tx.execute('''
UPDATE public.constellation_anchor SET x_units = 3, y_units = 2
WHERE viewer_id = '$viewer' AND person_id = '$firstPeer'
''');
          },
        );

        expect(
          run.beforeReleaseRevision.value,
          greaterThan(seeded.afterRevision.value),
        );
        expect(run.result.beforeRevision, run.beforeReleaseRevision);
        expect(
          run.result.afterRevision.value,
          run.beforeReleaseRevision.value + BigInt.one,
        );
        expect(run.result.results.single.status, AnchorOpStatus.ok);
        final projected = {
          for (final anchor in (await freshAnchors()).anchors)
            anchor.target: anchor.position,
        };
        expect(
          projected[ConstellationAnchorTarget.person(firstPeer)],
          position(3, 2),
        );
        expect(
          projected[ConstellationAnchorTarget.person(secondPeer)],
          position(2, -1),
        );
        await expectRetriedWriteTransaction(
          'own-placement',
          run.blockedTransactionStartedAt,
        );
        expect(
          (await opLog()).where((row) => row['id'] == 'own-placement'),
          hasLength(1),
        );
        await expectFreshProjection(run.result);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    for (final revokeWithUserDeletion in [false, true]) {
      test(
        revokeWithUserDeletion
            ? 'target deletions retain tombstones during concurrent person deletion and placement'
            : 'target deletions retain tombstones during concurrent visibility revocation and placement',
        () async {
          await apply([
            upsert('seed-person', ConstellationAnchorTarget.person(firstPeer)),
            upsert('seed-beacon', ConstellationAnchorTarget.beacon(openBeacon)),
          ]);

          final pinnedBefore = await readStoredConstellationAnchors(
            session.writer,
            viewerId: viewer,
          );
          final requestBefore = pinnedBefore.singleWhere(
            (row) => row['beacon_id'] == openBeacon,
          );
          final personBefore = pinnedBefore.singleWhere(
            (row) => row['person_id'] == firstPeer,
          );
          final run = await applyWhileCursorLocked(
            [
              upsert(
                'revoked-placement',
                ConstellationAnchorTarget.person(firstPeer),
                x: 3,
              ),
              upsert(
                'surviving-placement',
                ConstellationAnchorTarget.person(secondPeer),
                x: 2,
              ),
            ],
            foreignMutation: (tx) async {
              if (revokeWithUserDeletion) {
                // Both pinned targets are explicitly deleted. Account deletion
                // alone clears beacon.user_id and does not tombstone a Request.
                await tx.execute(
                  "DELETE FROM public.beacon WHERE user_id = '$firstPeer'",
                );
                await tx.execute(
                  'DELETE FROM public."user" WHERE id = \'$firstPeer\'',
                );
              } else {
                await tx.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$firstPeer', '$firstPeer')
''');
                await tx.execute(
                  "DELETE FROM public.beacon WHERE id = '$openBeacon'",
                );
              }
            },
          );

          expect(run.result.beforeRevision, run.beforeReleaseRevision);
          expect(
            run.result.afterRevision.value,
            run.beforeReleaseRevision.value +
                BigInt.from(revokeWithUserDeletion ? 1 : 2),
          );
          expect(run.result.results.map((r) => r.status), [
            if (revokeWithUserDeletion)
              AnchorOpStatus.rejected
            else
              AnchorOpStatus.ok,
            AnchorOpStatus.ok,
          ]);
          expect(run.result.results.map((r) => r.reason), [
            if (revokeWithUserDeletion) 'target_not_found' else null,
            null,
          ]);
          final snapshot = await freshAnchors();
          expect(
            snapshot.anchors.map((a) => a.target),
            unorderedEquals([
              if (revokeWithUserDeletion)
                ConstellationAnchorTarget.person(firstPeer),
              ConstellationAnchorTarget.person(secondPeer),
              ConstellationAnchorTarget.beacon(openBeacon),
            ]),
          );
          expect(
            snapshot.pinnedPeers.map((p) => p.id),
            unorderedEquals([
              if (revokeWithUserDeletion) firstPeer,
              secondPeer,
            ]),
          );
          expect(snapshot.pinnedRequests.map((r) => r.id), [openBeacon]);
          expect(snapshot.serverFilteredBeaconIds, isEmpty);
          final wire = constellationAnchorProjectionToGqlMap(snapshot);
          final requestRecord =
              (wire['pinnedRequests'] as List<dynamic>).single
                  as Map<String, dynamic>;
          expect(requestRecord['id'], openBeacon);
          final placeholders = [
            requestRecord,
            if (revokeWithUserDeletion)
              (wire['pinnedPeers'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()
                  .singleWhere((record) => record['id'] == firstPeer),
          ];
          const identityFields = {
            'id',
            'kind',
            'targetKind',
            'pinState',
            'visible',
          };
          for (final placeholder in placeholders) {
            expect(placeholder['pinState'], 'tombstone');
            for (final entry in placeholder.entries) {
              if (!identityFields.contains(entry.key)) {
                expect(
                  entry.value,
                  isNull,
                  reason:
                      'A deleted target placeholder must not expose ${entry.key}',
                );
              }
            }
          }
          final retained = await readStoredConstellationAnchors(
            session.writer,
            viewerId: viewer,
          );
          expect(retained, hasLength(3));
          expectRetainedPinTombstone(
            retained.singleWhere((row) => row['id'] == requestBefore['id']),
            requestBefore,
            ConstellationAnchorTarget.beacon(openBeacon),
          );
          if (revokeWithUserDeletion) {
            expectRetainedPinTombstone(
              retained.singleWhere((row) => row['id'] == personBefore['id']),
              personBefore,
              ConstellationAnchorTarget.person(firstPeer),
            );
          }
          // This checks cleared live FKs; the retained-row checks forbid losing pins.
          final beaconRows = await session.writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$openBeacon'
''');
          expect(beaconRows.single.single, 0);
          await expectRetriedWriteTransaction(
            'surviving-placement',
            run.blockedTransactionStartedAt,
          );
          await expectFreshProjection(run.result);
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  });

  group('anchor batch visibility service recovery', () {
    test(
      'writes during an MR outage and replays the same ids after recovery',
      () async {
        final seeded = await apply([
          upsert(
            'seed-before-outage',
            ConstellationAnchorTarget.person(firstPeer),
          ),
        ]);
        final ops = [
          delete('outage-delete', ConstellationAnchorTarget.person(firstPeer)),
          upsert(
            'outage-placement',
            ConstellationAnchorTarget.person(secondPeer),
          ),
        ];
        await session.writer.execute(
          'INSERT INTO anchor_batch_probe.visibility_outage VALUES (true)',
        );
        late AnchorApplyBatchResult duringOutage;
        try {
          duringOutage = await apply(ops);
          expect(
            duringOutage.results.map((r) => r.status),
            everyElement(AnchorOpStatus.ok),
          );
          expect(
            duringOutage.results.map((r) => r.replayed),
            everyElement(isFalse),
          );
          expect(duringOutage.beforeRevision, seeded.afterRevision);
          expect(
            duringOutage.afterRevision.value,
            seeded.afterRevision.value + BigInt.from(2),
          );
          expect(
            (await opLog()).map((row) => row['id']),
            containsAll([
              'seed-before-outage',
              'outage-delete',
              'outage-placement',
            ]),
          );
        } finally {
          await session.writer.execute(
            'DELETE FROM anchor_batch_probe.visibility_outage',
          );
        }

        final beforeReplay = await databaseState();
        final recovered = await apply(ops);
        expect(await databaseState(), beforeReplay);
        expect(recovered.results.map((r) => r.replayed), everyElement(isTrue));

        expect(recovered.results.map((r) => r.clientOpId), [
          'outage-delete',
          'outage-placement',
        ]);
        expect(recovered.results.map((r) => r.status), [
          AnchorOpStatus.ok,
          AnchorOpStatus.ok,
        ]);
        expect(recovered.beforeRevision, duringOutage.afterRevision);
        expect(
          recovered.afterRevision.value,
          duringOutage.afterRevision.value,
        );
        expect(
          (await freshAnchors()).anchors.single.target,
          ConstellationAnchorTarget.person(secondPeer),
        );
        expect(await opLog(), hasLength(3));
        await expectFreshProjection(recovered);
      },
    );
  });

  group('independent anchor reads after batch writes', () {
    test(
      'includes existing anchors and first pins in the fresh ANCHORS projection',
      () async {
        await apply([
          upsert('existing-peer', ConstellationAnchorTarget.person(secondPeer)),
        ]);
        final result = await apply([
          upsert('first-pin-peer', ConstellationAnchorTarget.person(firstPeer)),
          upsert(
            'first-pin-beacon',
            ConstellationAnchorTarget.beacon(openBeacon),
          ),
        ]);

        expect(
          result.results.every((r) => r.status == AnchorOpStatus.ok),
          isTrue,
        );
        expect((await freshAnchors()).anchors, hasLength(3));
        expect((await freshAnchors()).pinnedPeers.map((p) => p.id).toSet(), {
          firstPeer,
          secondPeer,
        });
        expect((await freshAnchors()).pinnedRequests.map((r) => r.id), [
          openBeacon,
        ]);
        await expectFreshProjection(result);
      },
    );

    test(
      'accepts a filter-hidden target and reports it in the complete projection',
      () async {
        final result = await apply([
          upsert('closed-pin', ConstellationAnchorTarget.beacon(closedBeacon)),
        ]);

        expect(result.results.single.status, AnchorOpStatus.ok);
        expect((await freshAnchors()).anchors, hasLength(1));
        expect(
          (await freshAnchors()).anchors.single.target,
          ConstellationAnchorTarget.beacon(closedBeacon),
        );
        expect((await freshAnchors()).pinnedRequests, isEmpty);
        expect((await freshAnchors()).serverFilteredBeaconIds, [closedBeacon]);
        expect((await freshAnchors()).serverFilteredBeaconCount, 1);
        final stored = await session.writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$closedBeacon'
''');
        expect(stored.single.single, 1);
        await expectFreshProjection(result);
      },
    );

    test(
      'uses requested filters on independent reads after replay',
      () async {
        const showClosedParticipated = (
          context: kConstellationContext,
          filters: ConstellationFieldMembershipFilters(
            showClosed: true,
            participatedOnly: true,
          ),
        );
        final ops = [
          upsert('closed-pin', ConstellationAnchorTarget.beacon(closedBeacon)),
          upsert('open-pin', ConstellationAnchorTarget.beacon(openBeacon)),
        ];
        final first = await apply(ops);
        final beforeReplay = await databaseState();

        final replay = await apply(
          ops,
          projectionParams: showClosedParticipated,
        );

        expect(_resultValues(replay), _resultValues(first));
        expect(replay.afterRevision, first.afterRevision);
        expect(await databaseState(), beforeReplay);
        expect(
          (await freshAnchors(
            projectionParams: showClosedParticipated,
          )).pinnedRequests.map((r) => r.id),
          [
            closedBeacon,
          ],
        );
        expect(
          (await freshAnchors(
            projectionParams: showClosedParticipated,
          )).serverFilteredBeaconIds,
          [openBeacon],
        );
        await expectFreshProjection(
          replay,
          projectionParams: showClosedParticipated,
        );
      },
    );
  });
}

Future<DateTime> _waitForCursorForUpdate(
  Session observer, {
  required int blockerPid,
  required bool Function() hasCompleted,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < kStableStateWait) {
    final rows = await observer.execute('''
SELECT a.xact_start FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.pid <> pg_backend_pid()
  AND $blockerPid = ANY(pg_blocking_pids(a.pid))
  AND a.wait_event_type = 'Lock'
  AND a.query ILIKE '%constellation_anchor_cursor%'
  AND a.query ~* 'FOR[[:space:]]+UPDATE'
''');
    if (rows.isNotEmpty) {
      expect(rows, hasLength(1));
      return rows.single.single! as DateTime;
    }
    if (hasCompleted()) {
      fail('Batch completed without waiting for the viewer cursor FOR UPDATE.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Batch did not wait for the viewer cursor FOR UPDATE within $kStableStateWait.',
  );
}

List<Object> _resultValues(AnchorApplyBatchResult batch) => [
  for (final result in batch.results)
    (
      result.clientOpId,
      result.status,
      result.reason,
      result.resultingTargetRevision,
      result.position,
    ),
];

// Same real-DB profile adapter used by the projection-reader tests: the batch
// and independent ANCHORS read resolve profiles from the same disposable DB.
final class _PgProfileLookup implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  _PgProfileLookup(this._database);

  final TenturaDb _database;

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) return {};
    final users = await _database.managers.users
        .filter((u) => u.id.isIn(idList))
        .get();
    return {
      for (final user in users)
        user.id: UserEntity(id: user.id, displayName: user.displayName),
    };
  }

  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async {
    final entities = await userEntitiesByIds(ids);
    return {
      for (final entry in entities.entries)
        entry.key: UserPublicRecord(
          id: entry.value.id,
          displayName: entry.value.displayName,
          description: entry.value.description,
          isMutualFriend: reciprocalPeerIds.contains(entry.key),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(
            entry.key,
          ),
          userAvailability: null,
        ),
    };
  }
}
