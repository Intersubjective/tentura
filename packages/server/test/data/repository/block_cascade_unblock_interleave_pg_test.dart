@Tags(['pg'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// A cascade batch that races an unblock must take the lock sequence
/// hierarchy scope → intent row, and must re-read the intent only once it
/// holds the hierarchy lock. A batch queued behind an unblock therefore finds
/// the intent gone and inserts nothing, so no inherited block outlives the
/// unblock. Each race waits until the batch is observed blocked on the held
/// lock before the unblock commits, so the overlap is proven, not assumed.
const _blockerId = 'Ublkuiblocker1';
const _originId = 'Ublkuiorigin001';
const _childAId = 'Ublkuichilda001';
const _childBId = 'Ublkuichildb001';
const _rootId = 'Ublkuiroot00001';
const _budget = Duration(seconds: 10);
const _hierarchyLock =
    "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))";
const _pauseKey = "hashtextextended('tentura.test.cascade_pause', 0)";
const _fixtureIds = [_rootId, _blockerId, _originId, _childAId, _childBId];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BLOCK_CASCADE_UNBLOCK_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bcu',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Cascade batch racing an unblock', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb dbA;
    late TenturaDb dbB;
    late UserBlockRepository workerRepo;
    late UserBlockRepository unblockRepo;
    late Env env;
    late int workerPid;
    late int unblockPid;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      env = Env(
        environment: Environment.test,
        pgHost: target.databaseEnv.pgHost,
        pgPort: target.databaseEnv.pgPort,
        pgDatabase: target.databaseName,
        pgUsername: target.databaseEnv.pgUsername,
        pgPassword: target.databaseEnv.pgPassword,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      );
      dbA = openDisposablePgDatabase(target);
      dbB = openDisposablePgDatabase(target);
      workerRepo = UserBlockRepository(env, dbA);
      unblockRepo = UserBlockRepository(env, dbB);

      // Pause point: the wrapper returns the candidates only after taking a
      // shared advisory lock, so a test holding it exclusively freezes a batch
      // exactly after it has begun processing candidates.
      await writer.execute(
        'ALTER FUNCTION public.block_cascade_candidates( '
        'text, text, smallint, integer, integer) '
        'RENAME TO block_cascade_candidates_unpaused',
      );
      await writer.execute('''
CREATE FUNCTION public.block_cascade_candidates(
  _blocker text, _root text, _mode smallint, _max_depth integer,
  _limit integer) RETURNS TABLE(user_id text, depth integer)
LANGUAGE plpgsql AS \$\$
BEGIN
  RETURN QUERY SELECT c.user_id, c.depth
    FROM public.block_cascade_candidates_unpaused(
      _blocker, _root, _mode, _max_depth, _limit) c;
  PERFORM pg_advisory_xact_lock_shared($_pauseKey);
END;
\$\$
''');
    });

    setUp(() async {
      await _resetFixture(writer, env);
      workerPid = await _backendPid(dbA);
      unblockPid = await _backendPid(dbB);
    });

    tearDownAll(() async {
      await dbB.close();
      await tearDownDisposablePgWriter(session: session, drift: dbA);
    });

    Future<Connection> holderWithHierarchyLock() async {
      final holder = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(holder.close);
      await holder.execute('BEGIN');
      await holder.execute(_hierarchyLock);
      return holder;
    }

    Future<void> blockWithCascade({required int status}) async {
      await workerRepo.block(
        blockerId: _blockerId,
        blockedId: _originId,
        cascadeMode: 1,
      );
      if (status == 1) {
        await writer.execute('''
UPDATE public.user_block_intent
SET cascade_status = 1, cascade_snapshot_at = now()
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
''');
      }
    }

    Future<void> unblockOn(Connection holder) async {
      await holder.execute('''
DELETE FROM public.user_block
WHERE blocker_id = '$_blockerId' AND origin_id = '$_originId'
''');
      await holder.execute('''
DELETE FROM public.user_block_intent
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
''');
      await holder.execute('COMMIT');
    }

    for (final status in [0, 1]) {
      final label = status == 0 ? 'an initial' : 'a resumed';

      test(
        '$label cascade batch waiting for the hierarchy lock holds no row '
        'lock on the intent',
        () async {
          await blockWithCascade(status: status);
          final holder = await holderWithHierarchyLock();
          final batch = workerRepo.materializeCascadeBatch(
            blockerId: _blockerId,
            blockedId: _originId,
            limit: 10,
          );
          unawaited(batch.then<void>((_) {}, onError: (_) {}));
          await _waitForLockWait(writer, workerPid);

          // Fails with lock_not_available while the batch already holds the
          // intent row, which is the reverse of the unblock's lock order.
          await writer.execute('''
SELECT 1 FROM public.user_block_intent
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
FOR UPDATE NOWAIT
''');

          await holder.execute('COMMIT');
          await batch.timeout(_budget);
        },
      );

      test(
        '$label cascade batch queued behind a committed unblock inserts no '
        'inherited block',
        () async {
          await blockWithCascade(status: status);
          final holder = await holderWithHierarchyLock();
          final batch = _settle(
            workerRepo.materializeCascadeBatch(
              blockerId: _blockerId,
              blockedId: _originId,
              limit: 10,
            ),
          );
          await _waitForLockWait(writer, workerPid);

          // The unblock runs on the lock holder, so it commits while the batch
          // is queued with whatever it has read so far.
          await unblockOn(holder).timeout(_budget);

          final outcome = await batch.timeout(_budget);
          expect(outcome.error, isNull, reason: 'the batch ends quietly');
          expect(outcome.value, 0, reason: 'nothing materialized');

          final survivors = await writer.execute('''
SELECT blocked_id FROM public.user_block
WHERE blocker_id = '$_blockerId' AND origin_id = '$_originId'
''');
          expect(survivors, isEmpty, reason: 'no block outlives the unblock');
          final intents = await writer.execute('''
SELECT 1 FROM public.user_block_intent
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
''');
          expect(intents, isEmpty);
        },
      );
    }

    Future<Connection> pauseHolder() async {
      final pauser = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      addTearDown(pauser.close);
      await pauser.execute('SELECT pg_advisory_lock($_pauseKey)');
      return pauser;
    }

    for (final status in [0, 1]) {
      final label = status == 0 ? 'an initial' : 'a resumed';

      test(
        '$label cascade batch that has begun processing candidates holds the '
        'hierarchy lock and the intent row lock',
        () async {
          await blockWithCascade(status: status);
          final pauser = await pauseHolder();
          final batch = workerRepo.materializeCascadeBatch(
            blockerId: _blockerId,
            blockedId: _originId,
            limit: 10,
          );
          unawaited(batch.then<void>((_) {}, onError: (_) {}));
          await _waitForLockWait(writer, workerPid);

          final free = (await writer.execute(
            'SELECT pg_try_advisory_lock(hashtextextended( '
            "'tentura.beacon_hierarchy.v1', 0))",
          )).single.single! as bool;
          if (free) {
            await writer.execute(
              'SELECT pg_advisory_unlock(hashtextextended( '
              "'tentura.beacon_hierarchy.v1', 0))",
            );
          }
          expect(free, isFalse, reason: 'hierarchy lock is held by the batch');
          await expectLater(
            writer.execute('''
SELECT 1 FROM public.user_block_intent
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
FOR UPDATE NOWAIT
'''),
            throwsA(isA<ServerException>()),
            reason: 'intent row is locked and revalidated by the batch',
          );

          await pauser.execute('SELECT pg_advisory_unlock($_pauseKey)');
          await batch.timeout(_budget);
        },
      );

      test(
        'an unblock racing $label cascade batch paused after reading its '
        'candidates deadlocks nothing and leaves no inherited block',
        () async {
          await blockWithCascade(status: status);
          final pauser = await pauseHolder();
          final batch = _settle(
            workerRepo.materializeCascadeBatch(
              blockerId: _blockerId,
              blockedId: _originId,
              limit: 10,
            ),
          );
          await _waitForLockWait(writer, workerPid);

          var unblockDone = false;
          final unblock = _settle(
            unblockRepo.unblock(blockerId: _blockerId, blockedId: _originId),
          );
          unawaited(unblock.then((_) => unblockDone = true));
          // The unblock either queues behind the batch or commits outright.
          final deadline = DateTime.now().add(_budget);
          while (!unblockDone && DateTime.now().isBefore(deadline)) {
            final queued = await writer.execute(
              'SELECT 1 FROM pg_stat_activity WHERE pid = $unblockPid '
              "AND wait_event_type = 'Lock'",
            );
            if (queued.isNotEmpty) break;
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }

          await pauser.execute('SELECT pg_advisory_unlock($_pauseKey)');
          final outcomes = await Future.wait([batch, unblock]).timeout(_budget);
          for (final o in outcomes) {
            expect('${o.error}', isNot(contains('deadlock')));
          }
          expect(outcomes[1].error, isNull, reason: 'unblock succeeds');

          final survivors = await writer.execute('''
SELECT blocked_id FROM public.user_block
WHERE blocker_id = '$_blockerId' AND origin_id = '$_originId'
''');
          expect(survivors, isEmpty, reason: 'no block outlives the unblock');
          final intents = await writer.execute('''
SELECT 1 FROM public.user_block_intent
WHERE blocker_id = '$_blockerId' AND blocked_id = '$_originId'
''');
          expect(intents, isEmpty);
        },
      );
    }
  });
}

typedef _Outcome = ({Object? error, Object? value});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    return (error: null, value: await action);
  } on Object catch (error) {
    return (error: error, value: null);
  }
}

Future<int> _backendPid(TenturaDb db) async {
  final row = await db
      .customSelect('SELECT pg_backend_pid() AS pid')
      .getSingle();
  return row.read<int>('pid');
}

/// Waits until backend [pid] is blocked on a heavyweight lock.
Future<void> _waitForLockWait(Connection writer, int pid) async {
  final deadline = DateTime.now().add(_budget);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT 1 FROM pg_stat_activity '
      "WHERE pid = $pid AND wait_event_type = 'Lock'",
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('backend $pid never blocked on a lock');
}

Future<void> _resetFixture(Connection writer, Env env) async {
  final ids = _fixtureIds.map((id) => "'$id'").join(', ');
  await writer.execute(
    'DELETE FROM public.user_block WHERE blocker_id IN ($ids) '
    'OR blocked_id IN ($ids)',
  );
  await writer.execute(
    'DELETE FROM public.user_block_intent WHERE blocker_id IN ($ids) '
    'OR blocked_id IN ($ids)',
  );
  await writer.execute(
    'DELETE FROM public.invite_genealogy '
    'WHERE descendant_user_id IN ($ids) OR ancestor_user_id IN ($ids)',
  );
  await writer.execute('DELETE FROM public."user" WHERE id IN ($ids)');

  final tRoot = DateTime.utc(2026);
  final tBranch = DateTime.utc(2026, 2);
  final tChild = DateTime.utc(2026, 3);
  for (final (id, at) in [
    (_rootId, tRoot),
    (_blockerId, tBranch),
    (_originId, tBranch),
    (_childAId, tChild),
    (_childBId, tChild),
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '${at.toIso8601String()}', '${at.toIso8601String()}')
''');
  }
  Future<void> edge(String ancestor, DateTime aAt, String child, DateTime cAt) =>
      writer.execute('''
INSERT INTO public.invite_genealogy (
  descendant_node_key, ancestor_node_key, descendant_user_id,
  ancestor_user_id, ancestor_user_created_at, descendant_user_created_at,
  created_at
) VALUES (
  '${InviteGenealogyNodeKey.derive(userId: child, env: env)}',
  '${InviteGenealogyNodeKey.derive(userId: ancestor, env: env)}',
  '$child', '$ancestor',
  '${aAt.toIso8601String()}', '${cAt.toIso8601String()}', now()
)
''');
  await edge(_rootId, tRoot, _blockerId, tBranch);
  await edge(_rootId, tRoot, _originId, tBranch);
  await edge(_originId, tBranch, _childAId, tChild);
  await edge(_originId, tBranch, _childBId, tChild);
}
