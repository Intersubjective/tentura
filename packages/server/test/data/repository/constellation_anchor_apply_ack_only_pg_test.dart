@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:get_it/get_it.dart';
import 'package:postgres/postgres.dart'
    show Connection, ServerException, Session;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

import '../../support/constellation_profiles_from_public_records.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/meritrank_blackhole.dart';
import '../../support/pg_wait.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_ACK_ONLY_TEST_DB',
    defaultNamePrefix: 'tentura_test_caack',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }
  final (blackhole, blackholeSkip) = await MeritRankBlackhole.probe();

  const viewer = 'Ucaackviewer001';
  const trustedPeer = 'Ucaackpeer00001';
  const strangerPeer = 'Ucaackstrang0001';
  const blockedPeer = 'Ucaackblocked001';
  const doomedPeer = 'Ucaackdoomed0001';
  const missingPeer = 'Ucaackmissing001';
  const missingBeacon = 'Bcaackmissing001';
  const openBeacon = 'Bcaackopen00001';

  late DisposablePgWriterSession session;
  late Connection backend;
  late TenturaDb db;
  late _WriteObservations observations;
  late _Profiles profiles;
  late ConstellationAnchorRepositoryPort repository;

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

  Future<AnchorApplyBatchResult> apply(List<AnchorApplyOp> ops) =>
      repository.applyBatch(viewerId: viewer, ops: ops);

  Future<List<String>> storedTargetIds() async {
    final rows = await session.writer.execute('''
SELECT coalesce(person_id, beacon_id)
FROM public.constellation_anchor
WHERE viewer_id = '$viewer'
ORDER BY 1
''');
    return [for (final row in rows) row.single! as String];
  }

  Future<ConstellationAnchor> storedAnchor(
    ConstellationAnchorTarget target,
  ) async {
    final rows = await session.writer.execute('''
SELECT x_units, y_units, coordinate_space_version, revision, placed_at
FROM public.constellation_anchor
WHERE viewer_id = '$viewer'
  AND ${target.kind == ConstellationAnchorTargetKind.person ? 'person_id' : 'beacon_id'} = '${target.id}'
''');
    expect(rows, hasLength(1));
    final row = rows.single;
    return ConstellationAnchor(
      target: target,
      position: ConstellationAnchorPosition(
        xUnits: (row[0]! as num).toDouble(),
        yUnits: (row[1]! as num).toDouble(),
        coordinateSpaceVersion: row[2]! as int,
      ),
      revision: ConstellationAnchorRevision(BigInt.from(row[3]! as int)),
      placedAt: row[4]! as DateTime,
    );
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

  Future<int> mrAttempts() async =>
      ((await backend.execute('SELECT public.mr_rpc_attempts()')).single.single!
              as num)
          .toInt();

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    // The connector counter is per backend: the apply and both measurements
    // must use this exact connection, including when the transaction rolls back.
    backend = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    observations = _WriteObservations();
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        backend,
        enableMigrations: false,
      ).interceptWith(observations),
    );
    profiles = _Profiles(db);
    GetIt.I.pushNewScope(
      init: (getIt) =>
          getIt.registerSingleton<UserProfileBatchLookup>(profiles),
    );
    repository = ConstellationAnchorRepository(db);
  });

  tearDownAll(() async {
    await GetIt.I.popScope();
    await db.close();
    if (backend.isOpen) await backend.close();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    final writer = session.writer;
    await writer.execute('DELETE FROM public.constellation_anchor');
    await writer.execute('DELETE FROM public.constellation_anchor_cursor');
    await writer.execute('DELETE FROM public.constellation_anchor_op_log');
    await writer.execute(
      'DELETE FROM public.constellation_anchor_target_watermark',
    );
    await writer.execute('DELETE FROM public.beacon');
    await writer.execute('DELETE FROM public.user_block');
    await writer.execute('DELETE FROM public.vote_user');
    await writer.execute('DELETE FROM public."user"');
    for (final id in [
      viewer,
      trustedPeer,
      strangerPeer,
      blockedPeer,
      doomedPeer,
    ]) {
      await writer.execute('''
INSERT INTO public."user"
  (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id',
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
    }
    await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewer', '$blockedPeer', '$blockedPeer')
''');
    await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewer', '$trustedPeer', 1, now(), now()),
       ('$trustedPeer', '$viewer', 1, now(), now()),
       ('$viewer', '$doomedPeer', 1, now(), now()),
       ('$doomedPeer', '$viewer', 1, now(), now())
''');
    await writer.execute('SELECT public.mr_reset()');
    for (final peer in [trustedPeer, doomedPeer]) {
      for (final (src, dst) in [(viewer, peer), (peer, viewer)]) {
        await writer.execute('''
SELECT public.mr_put_edge(
  '$src', '$dst', 0.75::double precision, '$kConstellationContext', 0)
''');
      }
    }
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable,
   created_at, updated_at, published_at)
VALUES ('$openBeacon', '$trustedPeer', '$openBeacon', 'anchor fixture',
        0, true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
        '2026-01-01T00:00:00Z')
''');
    await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id, revision)
VALUES ('$viewer', 0)
''');
    observations.clear();
    profiles.loads = 0;
  });

  group('anchor batch acknowledgement', () {
    test(
      'returns only revisions and operation results without a projection',
      () async {
        final result = await apply([
          upsert('ack-shape', ConstellationAnchorTarget.person(trustedPeer)),
        ]);
        expect(result.results.single.status, AnchorOpStatus.ok);
        expect(
          constellationAnchorsApplyResultToGqlMap(result).keys.toSet(),
          {'beforeRevision', 'afterRevision', 'results'},
        );
        expect(
          profiles.loads,
          0,
          reason: 'An acknowledgement needs no projection profiles.',
        );
        expect(
          observations.selects.where((sql) => sql.contains('person_visible_')),
          isEmpty,
          reason: 'Applying anchors must not prepare or read visibility.',
        );
      },
    );

    test(
      'an accepted upsert returns its complete stored row and placement time',
      () async {
        final target = ConstellationAnchorTarget.person(trustedPeer);
        final result = await apply([upsert('ack-row', target, x: 2, y: 3)]);
        final op = result.results.single;
        expect(op.status, AnchorOpStatus.ok);
        expect(op.replayed, isFalse);
        final anchor = op.anchor;
        expect(anchor, isA<ConstellationAnchor>());
        final row = anchor!;
        final stored = await storedAnchor(target);
        expect(row.target, target);
        expect(row.position, position(2, 3));
        expect(row.revision, op.resultingTargetRevision);
        expect(row.placedAt, stored.placedAt);
        expect(row, stored);
        expect(result.afterRevision, isNot(result.beforeRevision));
      },
    );

    test('stores a pin for a person outside the viewer visible set', () async {
      final visible = await session.writer.execute('''
SELECT peer_id FROM public.person_visible_peers_symmetric(
  '$viewer', '$kConstellationContext')
''');
      expect(visible.map((row) => row.single), isNot(contains(strangerPeer)));
      final result = await apply([
        upsert('pin-stranger', ConstellationAnchorTarget.person(strangerPeer)),
      ]);
      expect(result.results.single.status, AnchorOpStatus.ok);
      expect(await storedTargetIds(), [strangerPeer]);
    });

    test('stores a pin for a person blocked by the viewer', () async {
      final blocks = await session.writer.execute('''
SELECT 1 FROM public.user_block
WHERE blocker_id = '$viewer' AND blocked_id = '$blockedPeer'
''');
      expect(blocks, hasLength(1));
      final result = await apply([
        upsert('pin-blocked', ConstellationAnchorTarget.person(blockedPeer)),
      ]);
      expect(result.results.single.status, AnchorOpStatus.ok);
      expect(await storedTargetIds(), [blockedPeer]);
    });

    test(
      'applies with a blackholed MeritRank service and zero connector RPC attempts',
      () async {
        final hole = blackhole!;
        addTearDown(hole.release);
        await hole.engage();
        try {
          final before = await mrAttempts();
          final clock = Stopwatch()..start();
          AnchorApplyBatchResult? result;
          Object? failure;
          try {
            result = await apply([
              upsert(
                'pin-mr-down',
                ConstellationAnchorTarget.person(trustedPeer),
              ),
            ]);
          } on Object catch (error) {
            failure = error;
          }
          clock.stop();
          final after = await mrAttempts();
          expect(
            after - before,
            0,
            reason: 'Count every real connector attempt on the apply backend.',
          );
          expect(
            failure,
            isNull,
            reason: 'MeritRank availability cannot reject an anchor write.',
          );
          expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
          expect(result!.results.single.status, AnchorOpStatus.ok);
          expect(await storedTargetIds(), [trustedPeer]);
        } finally {
          await hole.release();
        }
      },
      skip: blackholeSkip,
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('anchor batch target existence', () {
    test(
      'missing person and Request targets reject only their operations',
      () async {
        final result = await apply([
          upsert('ok-person', ConstellationAnchorTarget.person(trustedPeer)),
          upsert('gone-person', ConstellationAnchorTarget.person(missingPeer)),
          upsert(
            'gone-beacon',
            ConstellationAnchorTarget.beacon(missingBeacon),
          ),
          upsert('ok-beacon', ConstellationAnchorTarget.beacon(openBeacon)),
        ]);
        expect(result.results, hasLength(4));
        final byId = {for (final op in result.results) op.clientOpId: op};
        expect(byId['ok-person']!.status, AnchorOpStatus.ok);
        expect(byId['ok-beacon']!.status, AnchorOpStatus.ok);
        expect(byId['gone-person']!.status, AnchorOpStatus.rejected);
        expect(byId['gone-person']!.reason, 'target_not_found');
        expect(byId['gone-beacon']!.status, AnchorOpStatus.rejected);
        expect(byId['gone-beacon']!.reason, 'target_not_found');
        expect(await storedTargetIds(), [openBeacon, trustedPeer]);
        expect(result.afterRevision, isNot(result.beforeRevision));
        for (final opId in ['ok-person', 'ok-beacon']) {
          final op = byId[opId]!;
          final target = opId == 'ok-person'
              ? ConstellationAnchorTarget.person(trustedPeer)
              : ConstellationAnchorTarget.beacon(openBeacon);
          expect(op.anchor, await storedAnchor(target));
        }
      },
    );

    test(
      'deleting a target after the snapshot returns target_not_found without storing a pin',
      () async {
        final blocker = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        addTearDown(blocker.close);
        final applyPid =
            (await backend.execute('SELECT pg_backend_pid()')).single.single!
                as int;
        late Future<AnchorApplyBatchResult> pending;
        var completed = false;
        await blocker.runTx((tx) async {
          final blockerPid =
              (await tx.execute('SELECT pg_backend_pid()')).single.single!
                  as int;
          await tx.execute('''
SELECT set_config('tentura.mutating_user_id', '$viewer', true)
''');
          await tx.execute('''
SELECT revision FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer' FOR UPDATE
''');
          observations.clear();
          pending = apply([
            upsert('race', ConstellationAnchorTarget.person(doomedPeer)),
          ]);
          unawaited(
            pending.then<void>(
              (_) {
                completed = true;
              },
              onError: (Object _) {
                completed = true;
              },
            ),
          );
          await _waitForCursor(
            session.writer,
            applyPid: applyPid,
            blockerPid: blockerPid,
            hasCompleted: () => completed,
          );
          // This commits after the apply's RR snapshot. The stale existence
          // read must not let a foreign-key error escape: retry the whole
          // transaction and reject the now-missing target in the fresh snapshot.
          await tx.execute(
            '''DELETE FROM public."user" WHERE id = '$doomedPeer' ''',
          );
        });
        final result = await pending.timeout(kCompletionWait);
        expect(result.results.single.status, AnchorOpStatus.rejected);
        expect(result.results.single.reason, 'target_not_found');
        expect(result.beforeRevision, ConstellationAnchorRevision.zero);
        expect(result.afterRevision, result.beforeRevision);
        expect(await storedTargetIds(), isEmpty);
      },
    );
  });

  group('anchor batch replay acknowledgement', () {
    final changedPayloads = <String, AnchorApplyOp Function()>{
      'position': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(trustedPeer),
        x: 2,
      ),
      'target': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(doomedPeer),
      ),
      'target kind': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.beacon(trustedPeer),
      ),
      'operation kind': () => AnchorApplyOp(
        clientOpId: 'payload-id',
        kind: AnchorOpKind.delete,
        target: ConstellationAnchorTarget.person(trustedPeer),
      ),
      'conditional revision': () => upsert(
        'payload-id',
        ConstellationAnchorTarget.person(trustedPeer),
        ifRevision: ConstellationAnchorRevision(BigInt.one),
      ),
    };
    for (final MapEntry(key: field, value: changedOp)
        in changedPayloads.entries) {
      test(
        'reusing an operation id with a different $field returns op_id_reused without changing stored state',
        () async {
          final target = ConstellationAnchorTarget.person(trustedPeer);
          final first = await apply([upsert('payload-id', target)]);
          expect(first.results.single.status, AnchorOpStatus.ok);
          final beforeReuse = await databaseState();
          final stored = await storedAnchor(target);

          final reused = await apply([changedOp()]);

          expect(reused.results.single.status, AnchorOpStatus.rejected);
          expect(reused.results.single.reason, 'op_id_reused');
          expect(reused.beforeRevision, first.afterRevision);
          expect(reused.afterRevision, first.afterRevision);
          expect(await repository.readWatermark(viewer), first.afterRevision);
          expect(await databaseState(), beforeReuse);
          expect(await storedAnchor(target), stored);
          expect(reused.results.single.replayed, isFalse);
          expect(reused.results.single.anchor, isNull);
        },
      );
    }

    test(
      'replay returns the stored row and replay flag without advancing revisions',
      () async {
        final target = ConstellationAnchorTarget.person(trustedPeer);
        final ops = [upsert('replay-row', target, x: 2, y: -3)];
        final first = await apply(ops);
        final stored = await storedAnchor(target);
        final second = await apply(ops);
        final executed = first.results.single;
        final replayed = second.results.single;
        expect(executed.status, AnchorOpStatus.ok);
        expect(replayed.status, AnchorOpStatus.ok);
        expect(executed.replayed, isFalse);
        expect(replayed.replayed, isTrue);
        final replayedRow = replayed.anchor;
        expect(replayedRow, isA<ConstellationAnchor>());
        expect(replayedRow, stored);
        expect(replayedRow, executed.anchor);
        expect(replayedRow!.placedAt, stored.placedAt);
        expect(
          replayed.resultingTargetRevision,
          executed.resultingTargetRevision,
        );
        expect(second.afterRevision, first.afterRevision);
        expect(second.beforeRevision, second.afterRevision);
        expect(await repository.readWatermark(viewer), first.afterRevision);
        expect(await storedAnchor(target), stored);
      },
    );
  });

  group('anchor batch atomicity', () {
    test(
      'a database error after earlier writes rolls back rows watermarks operation logs and revisions',
      () async {
        final person = ConstellationAnchorTarget.person(trustedPeer);
        final beacon = ConstellationAnchorTarget.beacon(openBeacon);
        final seeded = await apply([upsert('existing-placement', person)]);
        expect(seeded.results.single.status, AnchorOpStatus.ok);
        final before = await databaseState();
        final beforeRevision = await repository.readWatermark(viewer);
        final original = await storedAnchor(person);
        final ops = [
          upsert('rollback-move', person, x: 3, y: 4),
          upsert('rollback-fault', beacon, x: 5, y: 6),
        ];

        Future<void> removeFault() async {
          await session.writer.execute('''
DROP TRIGGER IF EXISTS ack_batch_rollback_probe
ON public.constellation_anchor_op_log
''');
          await session.writer.execute(
            'DROP FUNCTION IF EXISTS public.ack_batch_rollback_probe()',
          );
        }

        addTearDown(removeFault);
        // Fire at commit, once the earlier accepted operation has changed
        // every persistence table. The distinct precondition error prevents
        // an early failure from masquerading as a whole-batch rollback.
        await session.writer.execute('''
CREATE FUNCTION public.ack_batch_rollback_probe()
RETURNS trigger LANGUAGE plpgsql AS \$probe\$
BEGIN
  IF NEW.client_op_id = 'rollback-fault' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.constellation_anchor a
      JOIN public.constellation_anchor_target_watermark w
        ON w.viewer_id = a.viewer_id
        AND w.target_kind = 'PERSON' AND w.target_id = a.person_id
      JOIN public.constellation_anchor_op_log l
        ON l.viewer_id = a.viewer_id AND l.client_op_id = 'rollback-move'
      JOIN public.constellation_anchor_cursor c
        ON c.viewer_id = a.viewer_id
      WHERE a.viewer_id = '$viewer' AND a.person_id = '$trustedPeer'
        AND a.x_units = 3 AND a.y_units = 4
        AND a.revision = w.revision AND a.revision = l.revision
        AND a.revision > ${beforeRevision.value}
        AND c.revision > a.revision
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001',
        MESSAGE = 'ack_batch_rollback_probe_missing_earlier_write';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001',
      MESSAGE = 'ack_batch_rollback_probe';
  END IF;
  RETURN NEW;
END;
\$probe\$
''');
        await session.writer.execute('''
CREATE CONSTRAINT TRIGGER ack_batch_rollback_probe
AFTER INSERT ON public.constellation_anchor_op_log
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.ack_batch_rollback_probe()
''');

        await expectLater(
          apply(ops),
          throwsA(
            isA<ServerException>()
                .having((error) => error.code, 'SQLSTATE', 'P0001')
                .having(
                  (error) => error.message,
                  'fault after earlier writes',
                  'ack_batch_rollback_probe',
                ),
          ),
        );
        expect(await databaseState(), before);
        expect(await repository.readWatermark(viewer), beforeRevision);
        expect(await storedTargetIds(), [trustedPeer]);
        expect(await storedAnchor(person), original);

        await removeFault();
        final recovered = await apply(ops);
        expect(recovered.beforeRevision, beforeRevision);
        expect(recovered.results, hasLength(2));
        expect(await storedTargetIds(), [openBeacon, trustedPeer]);
        expect(await repository.readWatermark(viewer), recovered.afterRevision);
        for (final (op, target) in [
          (recovered.results[0], person),
          (recovered.results[1], beacon),
        ]) {
          expect(op.status, AnchorOpStatus.ok);
          expect(op.replayed, isFalse);
          expect(op.anchor, await storedAnchor(target));
        }
      },
    );
  });
}

Future<void> _waitForCursor(
  Session observer, {
  required int applyPid,
  required int blockerPid,
  required bool Function() hasCompleted,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < kStableStateWait) {
    final rows = await observer.execute('''
SELECT 1 FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.pid = $applyPid
  AND $blockerPid = ANY(pg_blocking_pids(a.pid))
  AND a.wait_event_type = 'Lock'
  AND a.query ILIKE '%constellation_anchor_cursor%'
  AND a.query ~* 'FOR[[:space:]]+UPDATE'
''');
    if (rows.isNotEmpty) return;
    if (hasCompleted()) {
      fail('The apply finished before reaching the held cursor lock.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'The apply did not reach the held cursor lock within $kStableStateWait.',
  );
}

final class _WriteObservations extends QueryInterceptor {
  final selects = <String>[];

  void clear() {
    selects.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement.toLowerCase());
    return super.runSelect(executor, statement, args);
  }
}

final class _Profiles implements UserProfileBatchLookup {
  _Profiles(this.db);

  final TenturaDb db;
  int loads = 0;

  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) {
    loads++;
    return constellationProfilesFromRecords(this, ids);
  }

  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async {
    final users = await db.managers.users
        .filter((u) => u.id.isIn(ids.toSet()))
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
    final users = await userEntitiesByIds(ids);
    return {
      for (final user in users.values)
        user.id: UserPublicRecord(
          id: user.id,
          displayName: user.displayName,
          description: user.description,
          isMutualFriend: reciprocalPeerIds.contains(user.id),
          subjectExplicitlyTrustsViewer: trustsViewerPeerIds.contains(user.id),
          userAvailability: null,
        ),
    };
  }
}
