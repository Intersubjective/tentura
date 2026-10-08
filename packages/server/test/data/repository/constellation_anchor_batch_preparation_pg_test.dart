@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Connection, Session;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

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
  const params = AnchorApplyParams(
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

  Future<AnchorApplyBatchResult> apply(
    List<AnchorApplyOp> ops, {
    AnchorApplyParams projectionParams = params,
  }) => repository.applyBatch(
    viewerId: viewer,
    ops: ops,
    params: projectionParams,
  );

  Future<int> rpcCount() async =>
      ((await backend.execute('SELECT public.mr_rpc_attempts()')).single.single!
              as num)
          .toInt();

  void clearObservations() {
    sql.statements.clear();
    profiles.loads.clear();
  }

  Future<void> expectFreshProjection(AnchorApplyBatchResult result) async {
    final snapshot = await fields.readSnapshot(
      viewerId: viewer,
      context: params.context,
      params: (
        filters: ConstellationFieldMembershipFilters.defaults,
        projection: ConstellationProjection.anchors,
      ),
    );
    expect(result.projection.revision, result.afterRevision);
    expect(snapshot.anchorProjection, result.projection);
  }

  void expectPreparedBeforeLock({required Set<String> requiredProfiles}) {
    final lock = sql.statements.indexWhere(_isCursorLock);
    expect(lock, greaterThanOrEqualTo(0));
    final preparation = sql.statements.take(lock).toList();
    expect(
      preparation.any((q) => q.contains('person_visible_')),
      isTrue,
      reason: 'Visibility must be prepared inside RR before cursor FOR UPDATE.',
    );
    expect(
      preparation.any((q) => q.contains('constellation_trust_edges')),
      isTrue,
      reason:
          'The potential holder/support closure needs prepared trust edges.',
    );
    expect(profiles.loads, hasLength(1));
    expect(profiles.loads.single.ids, requiredProfiles);
    expect(
      profiles.loads.single.statementIndex,
      lessThan(lock),
      reason:
          'Only required profiles are batch-fetched before the cursor lock.',
    );
    expect(profiles.loads.single.isolation, 'repeatable read');
    expect(profiles.loads.single.readOnly, 'off');
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
    repository = ConstellationAnchorRepository(db, profiles);
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

  group('anchor batch projection preparation', () {
    test(
      'first pins prepare requested people and beacon records before locking',
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
        expect(result.projection.pinnedPeers.map((p) => p.id), [peers[1]]);
        expect(result.projection.pinnedRequests.map((b) => b.id), [openBeacon]);
        expectPreparedBeforeLock(requiredProfiles: {peers.first, peers[1]});
        final lock = sql.statements.indexWhere(_isCursorLock);
        expect(
          sql.statements
              .take(lock)
              .any((q) => q.contains('from public.beacon ')),
          isTrue,
          reason: 'First-pin beacon readability and records must be prepared.',
        );
        await expectFreshProjection(result);
      },
    );

    test(
      'filter-hidden pins prepare readability without hydrating unrelated people',
      () async {
        final result = await apply([
          pin(
            'closed-pin',
            ConstellationAnchorTarget.beacon(closedBeacon),
          ),
        ]);
        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(
          result.projection.anchors.single.target,
          ConstellationAnchorTarget.beacon(closedBeacon),
        );
        expect(result.projection.pinnedRequests, isEmpty);
        expect(result.projection.serverFilteredBeaconIds, [closedBeacon]);
        // Even a hidden pin needs prepared readability, but no person profile.
        final lock = sql.statements.indexWhere(_isCursorLock);
        expect(
          sql.statements
              .take(lock)
              .any((q) => q.contains('from public.beacon ')),
          isTrue,
          reason:
              'Filter-hidden targets must be part of preparation before lock.',
        );
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
        expect(result.projection.anchors, hasLength(3));
        expect(result.projection.supportPeers.map((p) => p.id), [peers[1]]);
        expectPreparedBeforeLock(
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
          // Preflight on another backend proves the fixture really needs U
          // score calls. Its RPCs cannot populate the batch backend's memo or
          // contaminate that backend's measured mr_rpc_attempts() delta.
          final fixtureBefore =
              ((await fixture.writer.execute(
                        'SELECT public.mr_rpc_attempts()',
                      )).single.single!
                      as num)
                  .toInt();
          final visible = await fixture.writer.execute('''
SELECT peer_id FROM public.person_visible_peers_symmetric('$viewer', '$context')
''');
          final fixtureAfter =
              ((await fixture.writer.execute(
                        'SELECT public.mr_rpc_attempts()',
                      )).single.single!
                      as num)
                  .toInt();
          expect(visible.map((row) => row.single), containsAll(peers));
          expect(
            fixtureAfter - fixtureBefore,
            1 + fallbackCount,
            reason: 'The real fixture must exercise exactly U fallback RPCs.',
          );

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
              projectionParams: AnchorApplyParams(
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
          expect(result.projection.anchors, hasLength(64));
          expect(
            after - before,
            1 + fallbackCount,
            reason:
                'One shared visible set plus U real fallback-score RPCs, '
                'regardless of relevant trust churn or operation count.',
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
          expectPreparedBeforeLock(requiredProfiles: peers.toSet());
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
                result.projection.anchors.map((a) => a.target.id),
                containsAll([peers[0], peers[1], peers[2]]),
              );
            } else {
              expect(
                result.projection.anchors.map((a) => a.target.id),
                isNot(contains(peers.first)),
              );
            }
            expect(result.results.single.status, AnchorOpStatus.ok);
            // Inspect every discarded attempt too: prepare-before-lock cannot
            // be satisfied only after retrying an originally lock-first attempt.
            final firstLock = sql.statements.indexWhere(_isCursorLock);
            expect(
              sql.statements
                  .take(firstLock)
                  .any(
                    (q) => q.contains('person_visible_'),
                  ),
              isTrue,
              reason: 'The initial attempt must also prepare before lock.',
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
    'MeritRank outage aborts preparation before locking and leaves ids retryable',
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
      // Verify the real memo's fail-closed path, rather than simulating an empty
      // authorized population in the repository itself.
      final closed = await fixture.writer.execute('''
SELECT cardinality(public.person_visible_peer_ids_tx('$viewer', '${params.context}'))
''');
      expect(closed.single.single, 0);
      // Use the same retryability signal as withMutatingRepeatableRead.
      // An arbitrary exception (including an unclassified service failure)
      // must not satisfy the retryable-error contract. A bounded retry that
      // exhausts its deadline must retain a classified retryable cause.
      await expectLater(
        apply(ops),
        throwsA(
          anyOf(
            predicate<Object>(
              isPostgresDeadlockOrSerializationFailure,
              'an error recognized by the batch transaction retry classifier',
            ),
            isA<PostgresRetryDeadlineExceededException>().having(
              (error) => error.cause,
              'retryable cause',
              predicate<Object?>(
                (cause) =>
                    cause != null &&
                    isPostgresDeadlockOrSerializationFailure(cause),
                'a classified retryable error',
              ),
            ),
          ),
        ),
      );
      final lockedDuringOutage = sql.statements.any(_isCursorLock);
      final logs = await fixture.writer.execute(
        'SELECT count(*) FROM public.constellation_anchor_op_log',
      );
      final anchors = await fixture.writer.execute(
        'SELECT count(*) FROM public.constellation_anchor',
      );
      final revision = await fixture.writer.execute('''
SELECT revision FROM public.constellation_anchor_cursor WHERE viewer_id = '$viewer'
''');
      expect(logs.single.single, 0);
      expect(anchors.single.single, 0);
      expect((revision.single.single! as num).toInt(), 0);
      await fixture.writer.execute(
        'DELETE FROM public.batch_prepare_mr_outage',
      );
      final recovered = await apply(ops);
      expect(recovered.results.single.status, AnchorOpStatus.ok);
      expect(recovered.beforeRevision, ConstellationAnchorRevision.zero);
      expect(
        lockedDuringOutage,
        isFalse,
        reason:
            'Degraded MR must abort preparation before taking the cursor lock.',
      );
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
