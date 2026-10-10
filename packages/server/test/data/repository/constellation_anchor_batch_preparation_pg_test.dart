@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection, Session;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
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

import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

/// Observe application SQL, but count RPCs on the actual connector backend.
/// Neither the symmetric-function invocation count nor a mocked MR result is
/// a substitute for mr_rpc_attempts(). All service shims delegate to real MR.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_BATCH_PREPARATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_batch_prepare',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  const viewer = 'Ubatchprepview01';
  const openBeacon = 'Bbatchprepopen01';
  const closedBeacon = 'Bbatchprepclos01';
  const churnA = 'Ubatchprepchna01';
  final peers = [
    for (var i = 0; i < 64; i++) 'Ubatchprep${i.toString().padLeft(4, '0')}',
  ];
  const params = (
    context: kConstellationContext,
    filters: ConstellationFieldMembershipFilters.defaults,
  );
  late DisposablePgWriterSession fixture;
  late Connection backend;
  late Connection foreign;
  late TenturaDb db;
  late _SqlRecorder sql;
  late _Profiles profiles;
  late ConstellationAnchorRepository repository;
  late ConstellationFieldRepository fields;

  AnchorApplyOp pin(String opId, ConstellationAnchorTarget target) =>
      AnchorApplyOp(
        clientOpId: opId,
        kind: AnchorOpKind.upsert,
        target: target,
        position: const ConstellationAnchorPosition(
          xUnits: 2,
          yUnits: -3,
          coordinateSpaceVersion: 1,
        ),
        ifRevision: ConstellationAnchorRevision.zero,
      );

  var writeStatements = <String>[];
  var writeProfileLoads = 0;
  Future<AnchorApplyBatchResult> apply(
    List<AnchorApplyOp> ops, {
    ({String context, ConstellationFieldMembershipFilters filters})
        projectionParams =
        params,
  }) async {
    final result = await repository.applyBatch(viewerId: viewer, ops: ops);
    writeStatements = List.of(sql.statements);
    writeProfileLoads = profiles.loads.length;
    return result;
  }

  Future<ConstellationAnchorProjection> freshAnchors({
    String context = kConstellationContext,
  }) async => (await fields.readSnapshot(
    viewerId: viewer,
    context: context,
    params: (
      filters: params.filters,
      projection: ConstellationProjection.anchors,
    ),
  )).anchorProjection;

  Future<int> rpcCount() async =>
      ((await backend.execute('SELECT public.mr_rpc_attempts()')).single.single!
              as num)
          .toInt();

  void clearObservations() {
    sql.statements.clear();
    profiles.loads.clear();
  }

  Future<void> expectFreshProjection(AnchorApplyBatchResult result) async {
    final anchors = await freshAnchors();
    final full = await fields.readSnapshot(
      viewerId: viewer,
      context: params.context,
      params: (
        filters: params.filters,
        projection: ConstellationProjection.full,
      ),
    );
    expect(anchors, full.anchorProjection);
    expect(
      anchors.revision.value,
      greaterThanOrEqualTo(result.afterRevision.value),
    );
  }

  void expectWriteWithoutPreparation({required Set<String> requiredProfiles}) {
    final lock = writeStatements.indexWhere(_isCursorLock);
    expect(lock, greaterThanOrEqualTo(0));
    expect(
      writeStatements.where((q) => q.contains('person_visible_')),
      isEmpty,
    );
    expect(
      writeStatements.where((q) => q.contains('constellation_trust_edges')),
      isEmpty,
    );
    expect(writeProfileLoads, 0);
    expect(profiles.loads, isNotEmpty);
    for (final load in profiles.loads) {
      expect(load.ids, requiredProfiles);
      expect(load.statementIndex, greaterThan(lock));
      expect(load.isolation, 'repeatable read');
      expect(load.readOnly, 'on');
    }
    // The op-log rows are written in one server-side call (m0231).
    final writes = sql.statements.lastIndexWhere(
      (q) =>
          q.contains('insert into public.constellation_anchor_op_log') ||
          q.contains('public.constellation_anchor_apply_ops('),
    );
    expect(writes, greaterThan(lock));
    expect(
      sql.statements
          .skip(writes + 1)
          .any(
            (q) => q.contains('from public.constellation_anchor '),
          ),
      isTrue,
      reason: 'Final anchor rows must be re-read after all writes.',
    );
  }

  setUpAll(() async {
    fixture = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    foreign = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    sql = _SqlRecorder();
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        backend,
        enableMigrations: false,
      ).interceptWith(sql),
    );
    profiles = _Profiles(db, sql);
    repository = ConstellationAnchorRepository(
      db,
    );
    fields = ConstellationFieldRepository(db, profiles);
    await fixture.writer.execute(
      'CREATE TABLE public.batch_prepare_mr_outage (active boolean)',
    );
    await fixture.writer.execute('''
ALTER FUNCTION public.person_visible_peers_symmetric(text, text)
RENAME TO batch_prepare_visible_impl
''');
    await fixture.writer.execute(r'''
CREATE FUNCTION public.person_visible_peers_symmetric(viewer_id text, ctx text)
RETURNS TABLE(peer_id text) LANGUAGE plpgsql STABLE AS $probe$
BEGIN
  IF EXISTS (SELECT 1 FROM public.batch_prepare_mr_outage WHERE active) THEN
    RAISE EXCEPTION USING ERRCODE = '08006', MESSAGE = 'MeritRank unavailable';
  END IF;
  RETURN QUERY SELECT s.peer_id
  FROM public.batch_prepare_visible_impl(viewer_id, ctx) s;
END;
$probe$
''');
  });

  tearDownAll(() async {
    await db.close();
    if (backend.isOpen) await backend.close();
    await foreign.close();
    await tearDownDisposablePgWriter(session: fixture);
  });

  setUp(() async {
    final writer = fixture.writer;
    await writer.execute('DELETE FROM public.batch_prepare_mr_outage');
    await writer.execute('DELETE FROM public.constellation_anchor_op_log');
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.beacon_help_offer');
    await writer.execute('DELETE FROM public.beacon');
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    for (final id in [viewer, ...peers, churnA]) {
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    for (final peer in peers) {
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$peer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$peer', '$viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    for (final (id, status) in [(openBeacon, 0), (closedBeacon, 5)]) {
      await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   created_at, updated_at, published_at)
VALUES ('$id', '${peers.first}', '$id', 'projection fixture', $status, true,
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    // A closed Request is only readable (so pinnable) for a participant.
    await writer.execute('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, status, created_at, updated_at)
VALUES ('$closedBeacon', '$viewer', 0,
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewer')
''');
    clearObservations();
  });

  group('anchor batch acknowledgement and independent reads', () {
    test(
      'first pins write without preparing people or beacon profiles',
      () async {
        final result = await apply([
          pin('first-person', ConstellationAnchorTarget.person(peers[1])),
          pin(
            'first-beacon',
            ConstellationAnchorTarget.beacon(openBeacon),
          ),
        ]);
        expect(
          result.results.map((r) => r.status),
          everyElement(AnchorOpStatus.ok),
        );
        expect((await freshAnchors()).pinnedPeers.map((p) => p.id), [peers[1]]);
        expect((await freshAnchors()).pinnedRequests.map((b) => b.id), [
          openBeacon,
        ]);
        expectWriteWithoutPreparation(
          requiredProfiles: {peers.first, peers[1]},
        );
        final lock = sql.statements.indexWhere(_isCursorLock);
        expect(
          sql.statements
              .take(lock)
              .any((q) => q.contains('from public.beacon ')),
          isFalse,
          reason:
              'Beacon existence is checked after the cursor lock; readability is read-only.',
        );
        await expectFreshProjection(result);
      },
    );

    test(
      'filter-hidden pins are stored without hydrating unrelated people',
      () async {
        final result = await apply([
          pin(
            'closed-pin',
            ConstellationAnchorTarget.beacon(closedBeacon),
          ),
        ]);
        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(
          (await freshAnchors()).anchors.single.target,
          ConstellationAnchorTarget.beacon(closedBeacon),
        );
        expect((await freshAnchors()).pinnedRequests, isEmpty);
        expect((await freshAnchors()).serverFilteredBeaconIds, [closedBeacon]);
        expect(profiles.loads.expand((load) => load.ids), isEmpty);
        await expectFreshProjection(result);
      },
    );

    test(
      'existing pins and new holders prepare their support closure before locking',
      () async {
        await apply([
          pin('seed-existing', ConstellationAnchorTarget.person(peers[0])),
        ]);
        // The new holder is reachable only through peers[1]. Visibility uses
        // real MR in both directions; profiles must include that support peer
        // while omitting the other 61 visible peers.
        await fixture.writer.execute('''
DELETE FROM public.vote_user
WHERE (subject = '$viewer' AND object = '${peers[2]}')
   OR (subject = '${peers[2]}' AND object = '$viewer')
''');
        await fixture.writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('${peers[1]}', '${peers[2]}', 1, now(), now()),
       ('${peers[2]}', '${peers[1]}', 1, now(), now())
''');
        // Visibility for peers[2] comes from real MR edges alone, so no
        // explicit viewer<->peers[2] trust edge exists to shortcut the path.
        await fixture.writer.execute('SELECT public.mr_reset()');
        for (final (src, dst) in [(viewer, peers[2]), (peers[2], viewer)]) {
          await fixture.writer.execute('''
SELECT public.mr_put_edge('$src', '$dst', 0.75::double precision, '${params.context}', 0)
''');
        }
        clearObservations();
        final result = await apply([
          pin('add-person', ConstellationAnchorTarget.person(peers[2])),
          pin('add-beacon', ConstellationAnchorTarget.beacon(openBeacon)),
        ]);
        expect(
          result.results.map((r) => r.status),
          everyElement(AnchorOpStatus.ok),
        );
        expect((await freshAnchors()).anchors, hasLength(3));
        expect((await freshAnchors()).supportPeers.map((p) => p.id), [
          peers[1],
        ]);
        expectWriteWithoutPreparation(
          requiredProfiles: {peers[0], peers[1], peers[2]},
        );
        await expectFreshProjection(result);
      },
    );
  });

  group('anchor batch shared visibility and bounded reads', () {
    for (final context in [kConstellationContext, 'batch-preparation-alt']) {
      for (final fallbackCount in [0, 8]) {
        test('64 person operations batch-load dedupe and watermarks with '
            '$fallbackCount fallback-score calls under viewer trust churn '
            'in context "$context"', () async {
          final fallbackTargets = peers.take(fallbackCount).toSet();
          if (fallbackTargets.isNotEmpty) {
            final ids = fallbackTargets.map((id) => "'$id'").join(', ');
            // Explicit trust supplies the outgoing visibility signal, while
            // MR supplies only the incoming signal. With no viewer-to-target
            // MR path these batch targets are absent from mr_mutual_scores
            // and require real mr_node_score fallback RPCs to be authorized.
            await fixture.writer.execute('''
DELETE FROM public.vote_user
WHERE subject IN ($ids) AND object = '$viewer'
''');
          }
          await fixture.writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$churnA', 1, now(), now()),
       ('$churnA', '$viewer', 1, now(), now())
''');
          // The shared MR suite lock makes graph replacement safe. Following
          // the perf fixtures, publish real graph edges independently of SQL
          // explicit trust to create a deterministic fallback population in
          // each context. There are no mocked score or visibility results.
          await fixture.writer.execute('SELECT public.mr_reset()');
          for (final peer in [...peers, churnA]) {
            if (!fallbackTargets.contains(peer)) {
              await fixture.writer.execute('''
SELECT public.mr_put_edge('$viewer', '$peer', 0.75::double precision, '$context', 0)
''');
            }
            await fixture.writer.execute('''
SELECT public.mr_put_edge('$peer', '$viewer', 0.75::double precision, '$context', 0)
''');
          }

          final mutual = await fixture.writer.execute('''
SELECT CASE WHEN m.src = '$viewer' THEN m.dst ELSE m.src END AS peer_id
FROM public.mr_mutual_scores('$viewer', '$context') m
''');
          final mutualIds = mutual.map((row) => row.single! as String).toSet();
          expect(
            mutualIds.intersection(fallbackTargets),
            isEmpty,
            reason:
                'Fallback targets must be absent from the outbound MR list.',
          );
          if (fallbackCount > 0) {
            final ids = fallbackTargets.map((id) => "'$id'").join(', ');
            final explicit = await fixture.writer.execute('''
SELECT
  (SELECT count(*) FROM public.vote_user
   WHERE subject = '$viewer' AND object IN ($ids) AND amount > 0),
  (SELECT count(*) FROM public.vote_user
   WHERE subject IN ($ids) AND object = '$viewer' AND amount > 0)
''');
            expect(explicit.single[0], fallbackCount);
            expect(
              explicit.single[1],
              0,
              reason: 'Reciprocal SQL trust must not bypass fallback scores.',
            );
          }
          clearObservations();
          var stop = false;
          var commits = 0;
          final firstCommit = Completer<void>();
          final churn = () async {
            try {
              while (!stop) {
                final amount = commits.isEven ? -1 : 1;
                await foreign.runTx((tx) async {
                  // This edge is directly in the viewer's visibility inputs.
                  // It alternates between reciprocal trust and no outgoing
                  // positive signal, changing both MR and the frozen memo's
                  // direct-trust stamp while the person batch runs.
                  await tx.execute('''
UPDATE public.vote_user SET amount = $amount, updated_at = now()
WHERE subject = '$viewer' AND object = '$churnA'
''');
                  if (context != kConstellationContext) {
                    // vote_user's trigger publishes the default MR context;
                    // also keep the tested non-default context in sync.
                    await tx.execute('''
SELECT public.mr_put_edge('$viewer', '$churnA', $amount::double precision, '$context', 0)
''');
                  }
                });
                commits++;
                if (!firstCommit.isCompleted) firstCommit.complete();
              }
            } on Object catch (error, stack) {
              if (!firstCommit.isCompleted) {
                firstCommit.completeError(error, stack);
              }
              rethrow;
            }
          }();
          // Attach the error handler immediately; its errors are still awaited
          // and propagated in finally, including preflight/startup failures.
          unawaited(churn.then<void>((_) {}, onError: (Object _) {}));
          AnchorApplyBatchResult result;
          int before;
          int after;
          int commitsBefore;
          int commitsAfter;
          try {
            await firstCommit.future.timeout(kStableStateWait);
            before = await rpcCount();
            commitsBefore = commits;
            result = await apply(
              [
                for (var i = 0; i < peers.length; i++)
                  pin('person-$i', ConstellationAnchorTarget.person(peers[i])),
              ],
              projectionParams: (
                context: context,
                filters: params.filters,
              ),
            );
            commitsAfter = commits;
            after = await rpcCount();
          } finally {
            stop = true;
            await churn;
          }
          expect(
            commitsAfter,
            greaterThan(commitsBefore),
            reason:
                'Viewer visibility churn must commit during applyBatch itself.',
          );
          expect(
            result.results.map((r) => r.status),
            everyElement(AnchorOpStatus.ok),
          );
          expect((await freshAnchors(context: context)).anchors, hasLength(64));
          expect(
            after - before,
            0,
            reason:
                'Writes make no visibility or fallback-score RPCs, even during trust churn.',
          );
          final dedupe = sql.statements
              .where(
                (q) => q.contains('from public.constellation_anchor_op_log'),
              )
              .toList();
          final watermarks = sql.statements
              .where(
                (q) => q.contains(
                  'from public.constellation_anchor_target_watermark',
                ),
              )
              .toList();
          expect(
            dedupe,
            hasLength(1),
            reason: 'Dedupe records are batch-loaded.',
          );
          expect(
            watermarks,
            hasLength(1),
            reason: 'Target watermarks are batch-loaded.',
          );
          final lock = sql.statements.indexWhere(_isCursorLock);
          expect(sql.statements.indexOf(dedupe.single), greaterThan(lock));
          expect(sql.statements.indexOf(watermarks.single), greaterThan(lock));
          expectWriteWithoutPreparation(requiredProfiles: peers.toSet());
        });
      }
    }
  });

  group('anchor batch preparation across foreign writes', () {
    for (final mutation in [
      'anchor placement',
      'visibility revocation',
      'cascade deletion',
    ]) {
      test(
        '$mutation retries the prepared snapshot and returns final rows',
        () async {
          await apply([
            pin('seed-pin', ConstellationAnchorTarget.person(peers.first)),
          ]);
          clearObservations();
          Future<AnchorApplyBatchResult>? pending;
          Object? batchError;
          var completed = false;
          int? commitsBeforeRelease;
          try {
            await foreign.runTx((tx) async {
              final blockerPid =
                  ((await tx.execute('SELECT pg_backend_pid()')).single.single!)
                      as int;
              await tx.execute('''
SELECT revision FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer' FOR UPDATE
''');
              pending = apply([
                pin('new-pin', ConstellationAnchorTarget.person(peers[1])),
              ]);
              // Observe completion without creating an unhandled failed future.
              unawaited(
                pending!.then<void>(
                  (_) {
                    completed = true;
                  },
                  onError: (Object e) {
                    batchError = e;
                    completed = true;
                  },
                ),
              );
              await _waitForCursor(fixture.writer, blockerPid, () => completed);
              commitsBeforeRelease = sql.statements
                  .where(
                    (q) => q.startsWith('set transaction isolation level'),
                  )
                  .length;
              await tx.execute(
                "SELECT set_config('tentura.mutating_user_id', '$viewer', true)",
              );
              switch (mutation) {
                case 'anchor placement':
                  await tx.execute('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units, coordinate_space_version,
   revision, placed_at)
VALUES ('CAbatchforeign01', '$viewer', '${peers[2]}', 7, 8, 1, 0, 'epoch')
''');
                case 'visibility revocation':
                  await tx.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '${peers.first}', '$viewer')
''');
                case 'cascade deletion':
                  // A live owned Request would trip beacon_owner_or_deleted_ck.
                  await tx.execute(
                    "DELETE FROM public.beacon WHERE user_id = '${peers.first}'",
                  );
                  await tx.execute(
                    'DELETE FROM public."user" WHERE id = \'${peers.first}\'',
                  );
              }
              // All three paths must change the cursor after preparation's RR
              // snapshot, making SELECT FOR UPDATE retry the whole transaction.
              await tx.execute('''
UPDATE public.constellation_anchor_cursor SET revision = revision + 1
WHERE viewer_id = '$viewer'
''');
            });
            final result = await pending!.timeout(kCompletionWait);
            expect(batchError, isNull);
            expect(
              sql.statements
                  .where(
                    (q) => q.startsWith('set transaction isolation level'),
                  )
                  .length,
              greaterThan(commitsBeforeRelease!),
            );
            if (mutation == 'anchor placement') {
              expect(
                (await freshAnchors()).anchors.map((a) => a.target.id),
                containsAll([peers[0], peers[1], peers[2]]),
              );
            } else {
              expect(
                (await freshAnchors()).anchors.map((a) => a.target.id),
                isNot(contains(peers.first)),
              );
            }
            expect(result.results.single.status, AnchorOpStatus.ok);
            // Inspect every discarded attempt too: none may prepare visibility.
            final firstLock = sql.statements.indexWhere(_isCursorLock);
            expect(
              sql.statements
                  .take(firstLock)
                  .any(
                    (q) => q.contains('person_visible_'),
                  ),
              isFalse,
              reason: 'No attempt may prepare visibility before locking.',
            );
            await expectFreshProjection(result);
          } finally {
            if (pending != null) {
              await pending!.then<void>((_) {}, onError: (Object _) {});
            }
          }
        },
      );
    }
  });

  test(
    'MeritRank outage does not affect writes or replay',
    () async {
      final ops = [
        pin(
          'retry-after-outage',
          ConstellationAnchorTarget.person(peers.first),
        ),
      ];
      await fixture.writer.execute(
        'INSERT INTO public.batch_prepare_mr_outage VALUES (true)',
      );
      final before = await rpcCount();
      final accepted = await apply(ops);
      expect(await rpcCount() - before, 0);
      expect(accepted.results.single.status, AnchorOpStatus.ok);
      expect(accepted.results.single.replayed, isFalse);
      expect(accepted.results.single.anchor!.target, ops.single.target);
      expect(sql.statements.any(_isCursorLock), isTrue);
      expect(
        sql.statements.where((q) => q.contains('person_visible_')),
        isEmpty,
      );
      expect(profiles.loads, isEmpty);
      final logs = await fixture.writer.execute(
        'SELECT count(*) FROM public.constellation_anchor_op_log',
      );
      final anchors = await fixture.writer.execute(
        'SELECT count(*) FROM public.constellation_anchor',
      );
      expect(logs.single.single, 1);
      expect(anchors.single.single, 1);
      await fixture.writer.execute(
        'DELETE FROM public.batch_prepare_mr_outage',
      );
      final replay = await apply(ops);
      expect(replay.results.single.status, AnchorOpStatus.ok);
      expect(replay.results.single.replayed, isTrue);
      expect(replay.results.single.anchor, accepted.results.single.anchor);
      expect(replay.beforeRevision, accepted.afterRevision);
      expect(replay.afterRevision, accepted.afterRevision);
    },
  );
}

bool _isCursorLock(String sql) =>
    sql.contains('constellation_anchor_cursor') && sql.contains('for update');

final class _SqlRecorder extends QueryInterceptor {
  final statements = <String>[];

  void record(String statement) {
    var normalized = statement
        .toLowerCase()
        .replaceAll('"', '')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\t', ' ');
    while (normalized.contains('  ')) {
      normalized = normalized.replaceAll('  ', ' ');
    }
    statements.add(normalized.trim());
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    record(statement);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    record(statement);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    record(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    record(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    record(statement);
    return super.runDelete(executor, statement, args);
  }
}

Future<void> _waitForCursor(
  Session observer,
  int blockerPid,
  bool Function() completed,
) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < kStableStateWait) {
    final rows = await observer.execute('''
SELECT 1 FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND $blockerPid = ANY(pg_blocking_pids(a.pid))
  AND a.query ILIKE '%constellation_anchor_cursor%'
  AND a.query ~* 'FOR[[:space:]]+UPDATE'
''');
    if (rows.isNotEmpty) return;
    if (completed()) {
      fail('Batch finished before reaching the held cursor lock.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Batch did not reach the held cursor lock within $kStableStateWait.');
}

final class _Profiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) => constellationProfilesFromRecords(this, ids);

  _Profiles(this.db, this.sql);
  final TenturaDb db;
  final _SqlRecorder sql;
  final loads =
      <
        ({
          Set<String> ids,
          int statementIndex,
          String isolation,
          String readOnly,
        })
      >[];

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((u) => u.id.isIn(ids.toSet()))
        .get();
    return {
      for (final u in users)
        u.id: UserEntity(id: u.id, displayName: u.displayName),
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
    final at = sql.statements.length;
    final context = await db.customSelect('''
SELECT current_setting('transaction_isolation') AS isolation,
       current_setting('transaction_read_only') AS read_only
''').getSingle();
    loads.add(
      (
        ids: ids.toSet(),
        statementIndex: at,
        isolation: context.read<String>('isolation'),
        readOnly: context.read<String>('read_only'),
      ),
    );
    final users = await userEntitiesByIds(ids);
    return {
      for (final u in users.values)
        u.id: UserPublicRecord(
          id: u.id,
          displayName: u.displayName,
          description: u.description,
          isMutualFriend: reciprocalPeerIds.contains(u.id),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(u.id),
          userAvailability: null,
        ),
    };
  }
}
