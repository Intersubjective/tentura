@Tags(['pg', 'mr'])
library;

import 'package:drift/drift.dart' show Variable;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_publish_repository.dart';

import '../support/disposable_pg_target.dart';

const _alice = 'Ua3pubalice01';
const _bob = 'Ua3pubbob0001';
const _ids = [_alice, _bob];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_PUBLISH_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_publish',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late TrustPublishRepository repo;
  late TenturaDb db2;
  late TrustPublishRepository repo2;

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
      repo = TrustPublishRepository(db);
      // A second, independent pool: a second publisher process.
      db2 = TenturaDb(target.databaseEnv);
      repo2 = TrustPublishRepository(db2);
    });

    setUp(() async {
      await _cleanup(db);
      for (final id in _ids) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', now(), now())
ON CONFLICT (id) DO NOTHING
''',
        );
      }
      await db.customStatement('''
UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1
''');
      await db.customStatement('''
UPDATE public.trust_publisher_lease
SET owner = NULL, lease_until = 'epoch' WHERE id = 1
''');
      await db.customStatement(
        r'UPDATE public.mr_publish_epoch SET epoch = 0 WHERE id = true',
      );
    });

    tearDown(() => _cleanup(db));

    tearDownAll(() async {
      await db2.close();
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  test(
    'publishes target 0.5: MR edge exists, prev_sent_weight = 0.5, queue empty, epoch bumped',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      final token = await repo.acquireLease('me');
      expect(token, isNotNull);

      final rows = await repo.readBatch(200);
      expect(rows, hasLength(1));
      expect(rows.single.subject, _alice);
      expect(rows.single.object, _bob);
      expect(rows.single.target, 0.5);
      for (final r in rows) {
        await repo.publish(r);
      }
      await repo.sync();
      await repo.ack(token!, rows);

      expect(await _mrEdgeCount(db), 1);
      expect(await _prevSent(db), 0.5);
      expect(await _queueCount(db), 0);
      expect(await _epoch(db), greaterThan(BigInt.zero));
    },
    skip: skipReason,
  );

  test(
    'target changed between read and ack keeps the queue row; next run '
    'publishes the new value',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      final token = (await repo.acquireLease('me'))!;
      final rows = await repo.readBatch(200);
      await repo.publish(rows.single);
      await repo.sync();
      await db.customStatement(r'''
UPDATE public.user_trust_edge SET target_w = 0.8 WHERE subject = 'Ua3pubalice01'
''');

      await repo.ack(token, rows);

      expect(await _queueCount(db), 1);
      // Next run: fresh lease acquisition, as run() does.
      final token2 = (await repo.acquireLease('me'))!;
      final again = await repo.readBatch(200);
      expect(again.single.target, 0.8);
      await repo.publish(again.single);
      await repo.sync();
      await repo.ack(token2, again);
      expect(await _queueCount(db), 0);
      expect(await _prevSent(db), 0.8);
    },
    skip: skipReason,
  );

  test(
    'zero target with prev 0.5 deletes the MR edge and the edge row, '
    'leaving no queue row',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      var token = (await repo.acquireLease('me'))!;
      var rows = await repo.readBatch(200);
      await repo.publish(rows.single);
      await repo.sync();
      await repo.ack(token, rows);
      expect(await _mrEdgeCount(db), 1);

      await db.customStatement('''
UPDATE public.user_trust_edge SET target_w = 0 WHERE subject = 'Ua3pubalice01'
''');
      await db.customStatement('''
INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
VALUES ('Ua3pubalice01', 'Ua3pubbob0001')
ON CONFLICT DO NOTHING
''');
      token = (await repo.acquireLease('me'))!;
      rows = await repo.readBatch(200);
      expect(rows.single.target, 0);
      await repo.publish(rows.single);
      await repo.sync();
      await repo.ack(token, rows);

      expect(await _mrEdgeCount(db), 0);
      expect(await _edgeRowCount(db), 0);
      expect(await _queueCount(db), 0);
    },
    skip: skipReason,
  );

  test(
    'two publishers started together: only one gets the lease',
    () async {
      final tokens = await Future.wait([
        repo.acquireLease('one'),
        repo2.acquireLease('two'),
      ]);
      expect(tokens.whereType<int>(), hasLength(1));
      expect(await repo.leaseValid(tokens.whereType<int>().single), isTrue);
    },
    skip: skipReason,
  );

  test(
    'the lease owner can re-acquire and gets a higher token',
    () async {
      final t1 = (await repo.acquireLease('me'))!;
      final t2 = (await repo.acquireLease('me'))!;
      expect(t2, greaterThan(t1));
      expect(await repo.leaseValid(t1), isFalse);
      expect(await repo.leaseValid(t2), isTrue);
    },
    skip: skipReason,
  );

  test(
    'stale token (lease taken over): ack changes nothing',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      final stale = (await repo.acquireLease('old'))!;
      final rows = await repo.readBatch(200);
      await repo.publish(rows.single);
      await repo.sync();
      await db.customStatement('''
UPDATE public.trust_publisher_lease SET lease_until = now() - interval '1 second'
WHERE id = 1
''');
      final fresh = await repo.acquireLease('new');
      expect(fresh, isNotNull);
      expect(await repo.leaseValid(stale), isFalse);
      final epochBefore = await _epoch(db);

      await repo.ack(stale, rows);

      expect(await _prevSent(db), 0);
      expect(await _queueCount(db), 1);
      expect(await _epoch(db), epochBefore);
    },
    skip: skipReason,
  );

  test(
    'crash after sync before ack: next run republishes the same value and acks',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      final token = (await repo.acquireLease('me'))!;
      final first = await repo.readBatch(200);
      await repo.publish(first.single);
      await repo.sync();
      // process dies here: no ack

      final token2 = (await repo.acquireLease('me'))!;
      final second = await repo.readBatch(200);
      expect(second, hasLength(1));
      expect(second.single.target, 0.5);
      await repo.publish(second.single);
      await repo.sync();
      await repo.ack(token2, second);

      expect(token2, greaterThan(token));
      expect(await _mrEdgeCount(db), 1);
      expect(await _prevSent(db), 0.5);
      expect(await _queueCount(db), 0);
    },
    skip: skipReason,
  );

  test(
    'fail backs the row off, counts the attempt and records the error',
    () async {
      await _setEdge(db, target: 0.5, prev: 0);
      final rows = await repo.readBatch(200);

      await repo.fail(rows, 'boom');

      final row = await db.customSelect('''
SELECT attempts, last_error, next_attempt_at > now() AS later
FROM public.trust_publish_queue
''').getSingle();
      expect(row.read<int>('attempts'), 1);
      expect(row.read<String>('last_error'), 'boom');
      expect(row.read<bool>('later'), isTrue);
      expect(await repo.readBatch(200), isEmpty);
    },
    skip: skipReason,
  );

  test(
    'cutoverPending follows trust_cutover_state',
    () async {
      expect(await repo.cutoverPending(), isFalse);
      await db.customStatement('''
UPDATE public.trust_cutover_state SET status = 'pending' WHERE id = 1
''');
      expect(await repo.cutoverPending(), isTrue);
    },
    skip: skipReason,
  );
}

Future<void> _setEdge(
  TenturaDb db, {
  required double target,
  required double prev,
}) async {
  await db.customStatement(
    r'''
INSERT INTO public.user_trust_edge (subject, object, target_w, prev_sent_weight)
VALUES ($1, $2, $3, $4)
''',
    [_alice, _bob, target, prev],
  );
  await db.customStatement(
    r'''
INSERT INTO public.trust_publish_queue (subject_user_id, object_user_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING
''',
    [_alice, _bob],
  );
}

Future<int> _queueCount(TenturaDb db) async => (await db.customSelect(
  r'''
SELECT count(*)::int AS c FROM public.trust_publish_queue
WHERE subject_user_id = $1 AND object_user_id = $2
''',
  variables: [Variable<String>(_alice), Variable<String>(_bob)],
).getSingle()).read<int>('c');

Future<int> _edgeRowCount(TenturaDb db) async => (await db.customSelect(
  r'''
SELECT count(*)::int AS c FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
  variables: [Variable<String>(_alice), Variable<String>(_bob)],
).getSingle()).read<int>('c');

Future<double> _prevSent(TenturaDb db) async => (await db.customSelect(
  r'''
SELECT prev_sent_weight FROM public.user_trust_edge
WHERE subject = $1 AND object = $2
''',
  variables: [Variable<String>(_alice), Variable<String>(_bob)],
).getSingle()).read<double>('prev_sent_weight');

Future<BigInt> _epoch(TenturaDb db) async => (await db
    .customSelect(r'SELECT epoch FROM public.mr_publish_epoch WHERE id = true')
    .getSingle()).read<BigInt>('epoch');

/// `mr_edgelist()` is the only read API; match on the serialized row.
Future<int> _mrEdgeCount(TenturaDb db) async => (await db.customSelect(
  r'''
SELECT count(*)::int AS c
FROM mr_edgelist() e
WHERE to_jsonb(e)::text LIKE '%' || $1 || '%'
  AND to_jsonb(e)::text LIKE '%' || $2 || '%'
''',
  variables: [Variable<String>(_alice), Variable<String>(_bob)],
).getSingle()).read<int>('c');

Future<void> _cleanup(TenturaDb db) async {
  await db.customStatement(
    "SELECT mr_delete_edge('$_alice', '$_bob')",
  );
  final list = _ids.map((i) => "'$i'").join(', ');
  await db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($list) OR object_user_id IN ($list)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($list) OR object IN ($list)',
  );
  await db.customStatement('DELETE FROM public."user" WHERE id IN ($list)');
}
