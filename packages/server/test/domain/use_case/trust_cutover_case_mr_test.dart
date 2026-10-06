@Tags(['pg', 'mr'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_cutover_repository.dart';
import 'package:tentura_server/domain/port/trust_cutover_port.dart';
import 'package:tentura_server/domain/use_case/trust_cutover_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _alice = 'Ua4cutalice01';
const _bob = 'Ua4cutbob0001';
const _carol = 'Ua4cutcarol01';
const _dave = 'Ua4cutdave0001';
const _poll = 'Pa4cutpoll01';
const _variant = 'Va4cutvar0001';
const _ids = [_alice, _bob, _carol, _dave];

Env _testEnv() => Env(
  environment: Environment.test,
  publicOrigin: 'https://t.example',
  unsubscribeSigningSecret: 'secret',
);

/// Delegates to the real repository and counts/records port calls.
class _SpyPort implements TrustCutoverPort {
  _SpyPort(this._inner, this.log, {this.resetDelay = Duration.zero});

  final TrustCutoverPort _inner;
  final List<String> log;
  final Duration resetDelay;

  @override
  Future<bool> isDone() {
    log.add('isDone');
    return _inner.isDone();
  }

  @override
  Future<int?> acquire(String owner) {
    log.add('acquire');
    return _inner.acquire(owner);
  }

  @override
  Future<bool> renew(int token) {
    log.add('renew');
    return _inner.renew(token);
  }

  @override
  Future<List<(String, String)>> votePairs() {
    log.add('votePairs');
    return _inner.votePairs();
  }

  @override
  Future<void> projectPairs(int token, List<(String, String)> pairs) {
    log.add('projectPairs');
    return _inner.projectPairs(token, pairs);
  }

  @override
  Future<bool> banWallsDone() => _inner.banWallsDone();

  @override
  Future<List<(String, String)>> banPairs() => _inner.banPairs();

  @override
  Future<void> projectBanPairs(List<(String, String)> pairs) =>
      _inner.projectBanPairs(pairs);

  @override
  Future<void> markBanWallsDone() => _inner.markBanWallsDone();

  @override
  Future<void> reset(int token) async {
    log.add('reset');
    await Future<void>.delayed(resetDelay);
    return _inner.reset(token);
  }

  @override
  Future<void> init(int token) {
    log.add('init');
    return _inner.init(token);
  }

  @override
  Future<void> sync(int token) {
    log.add('sync');
    return _inner.sync(token);
  }

  @override
  Future<void> finish(int token) {
    log.add('finish');
    return _inner.finish(token);
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_CUTOVER_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_cutover',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late TenturaDb db2;
  late TrustCutoverRepository repo;
  late TrustCutoverRepository repo2;

  TrustCutoverCase buildCase(
    TenturaDb database,
    TrustCutoverPort port,
  ) => TrustCutoverCase(
    port,
    MutatingUnitOfWork(database),
    env: _testEnv(),
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
      db2 = TenturaDb(target.databaseEnv);
      repo = TrustCutoverRepository(db);
      repo2 = TrustCutoverRepository(db2);
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
UPDATE public.trust_cutover_state
SET status = 'pending', owner = NULL, lease_until = 'epoch' WHERE id = 1
''');
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
    'pending cutover loads exactly the positive vote edges plus polling '
    'edges into MR (no stale or negative edges), marks done, and a second '
    'run does nothing',
    () async {
      await _vote(db, _alice, _bob, 1);
      await _vote(db, _bob, _carol, 1);
      await _vote(db, _dave, _alice, -1);
      await _seedPolling(db);
      // Stale MR edge with no vote behind it: the reset must drop it.
      await db.customStatement(
        r"SELECT public.mr_put_edge($1, $2, 0.5, '', 0)",
        [_alice, _carol],
      );
      final log = <String>[];
      final useCase = buildCase(db, _SpyPort(repo, log));

      await useCase.runIfPending();

      expect(await _status(db), 'done');
      expect(await _owner(db), isNull);
      // 2 vote edges + author->variant + variant->polling. Since MeritRank
      // 0.12 (one node class) mr_edgelist() lists every edge, including the
      // variant->polling edge earlier versions hid.
      expect(await _mrEdgeCount(db), 4);
      expect(await _mrPairCount(db, _alice, _bob), 1);
      expect(await _mrPairCount(db, _bob, _carol), 1);
      expect(await _mrPairCount(db, _carol, _variant), 1);
      expect(await _mrPairCount(db, _variant, _poll), 1);
      expect(await _mrPairCount(db, _alice, _carol), 0, reason: 'stale edge');
      expect(await _mrPairCount(db, _dave, _alice), 0, reason: 'negative vote');
      expect(await _queueCount(db), 0);
      expect(await _unsentEdgeCount(db), 0);
      expect(log.where((e) => e == 'reset'), hasLength(1));

      log.clear();
      await useCase.runIfPending();

      for (final op in const [
        'acquire',
        'renew',
        'votePairs',
        'projectPairs',
        'reset',
        'init',
        'sync',
        'finish',
      ]) {
        expect(log, isNot(contains(op)), reason: 'second run called $op');
      }
      expect(await _mrEdgeCount(db), 4);
    },
    skip: skipReason,
  );

  test(
    'crash after reset/init/sync leaves pending; the next run finishes',
    () async {
      await _vote(db, _alice, _bob, 1);
      // First process: steps 1-3 by hand, then it dies before step 4.
      final token = (await repo.acquire('crashed'))!;
      await repo.projectPairs(token, await repo.votePairs());
      await repo.reset(token);
      await repo.init(token);
      await repo.sync(token);
      expect(await _status(db), 'pending');
      // The dead process's lease runs out.
      await db.customStatement('''
UPDATE public.trust_cutover_state SET lease_until = now() - interval '1 second'
WHERE id = 1
''');

      await buildCase(db, repo).runIfPending();

      expect(await _status(db), 'done');
      expect(await _mrEdgeCount(db), 1);
      expect(await _mrPairCount(db, _alice, _bob), 1);
      expect(await _unsentEdgeCount(db), 0);
      expect(await _queueCount(db), 0);
    },
    skip: skipReason,
  );

  test(
    'finish with a stale token changes nothing',
    () async {
      await _vote(db, _alice, _bob, 1);
      final stale = (await repo.acquire('old'))!;
      await db.customStatement('''
UPDATE public.trust_cutover_state SET lease_until = now() - interval '1 second'
WHERE id = 1
''');
      final fresh = await repo.acquire('new');
      expect(fresh, isNotNull);
      expect(fresh, greaterThan(stale));

      await repo.finish(stale);

      expect(await _status(db), 'pending');
      expect(await repo.isDone(), isFalse);
    },
    skip: skipReason,
  );

  test(
    'acquire: held lease blocks another owner, the owner may re-acquire',
    () async {
      final t1 = await repo.acquire('one');
      expect(t1, isNotNull);
      expect(await repo2.acquire('two'), isNull);
      final t2 = await repo.acquire('one');
      expect(t2, greaterThan(t1!));
      expect(await repo.renew(t1), isFalse);
      expect(await repo.renew(t2!), isTrue);
    },
    skip: skipReason,
  );

  test(
    'two runIfPending calls started together run mr_reset once and end '
    'in the correct state',
    () async {
      await _vote(db, _alice, _bob, 1);
      await _vote(db, _bob, _alice, 1);
      final log = <String>[];
      final a = buildCase(
        db,
        _SpyPort(repo, log, resetDelay: const Duration(milliseconds: 300)),
      );
      final b = buildCase(
        db2,
        _SpyPort(repo2, log, resetDelay: const Duration(milliseconds: 300)),
      );

      await Future.wait([a.runIfPending(), b.runIfPending()]);

      expect(log.where((e) => e == 'reset'), hasLength(1));
      expect(await _status(db), 'done');
      expect(await _mrEdgeCount(db), 2);
      expect(await _unsentEdgeCount(db), 0);
    },
    skip: skipReason,
  );
}

Future<void> _vote(TenturaDb db, String s, String o, int amount) =>
    db.customStatement(
      r'INSERT INTO public.vote_user (subject, object, amount) '
      r'VALUES ($1, $2, $3)',
      [s, o, amount],
    );

Future<String> _status(TenturaDb db) async => (await db
    .customSelect('SELECT status FROM public.trust_cutover_state WHERE id = 1')
    .getSingle()).read<String>('status');

Future<String?> _owner(TenturaDb db) async => (await db
    .customSelect('SELECT owner FROM public.trust_cutover_state WHERE id = 1')
    .getSingle()).read<String?>('owner');

Future<int> _queueCount(TenturaDb db) async => (await db
    .customSelect('SELECT count(*)::int AS c FROM public.trust_publish_queue')
    .getSingle()).read<int>('c');

/// Edges whose prev_sent_weight was not aligned with target_w.
Future<int> _unsentEdgeCount(TenturaDb db) async => (await db.customSelect(
  '''
SELECT count(*)::int AS c FROM public.user_trust_edge
WHERE prev_sent_weight IS DISTINCT FROM target_w
''',
).getSingle()).read<int>('c');

Future<int> _mrEdgeCount(TenturaDb db) async => (await db
    .customSelect('SELECT count(*)::int AS c FROM mr_edgelist()')
    .getSingle()).read<int>('c');

/// Edges between [x] and [y] in either direction (`mr_edgelist()` is the
/// only read API; match on the serialized row).
Future<int> _mrPairCount(TenturaDb db, String x, String y) async =>
    (await db.customSelect(
      r'''
SELECT count(*)::int AS c
FROM mr_edgelist() e
WHERE to_jsonb(e)::text LIKE '%' || $1 || '%'
  AND to_jsonb(e)::text LIKE '%' || $2 || '%'
''',
      variables: [Variable<String>(x), Variable<String>(y)],
    ).getSingle()).read<int>('c');

Future<void> _seedPolling(TenturaDb db) async {
  await db.customStatement(
    r'INSERT INTO public.polling (id, author_id, question) '
    r'VALUES ($1, $2, $3)',
    [_poll, _carol, 'q'],
  );
  await db.customStatement(
    r'INSERT INTO public.polling_variant (id, polling_id, description) '
    r'VALUES ($1, $2, $3)',
    [_variant, _poll, 'v'],
  );
  await db.customStatement(
    r'INSERT INTO public.polling_act (author_id, polling_id, polling_variant_id) '
    r'VALUES ($1, $2, $3)',
    [_carol, _poll, _variant],
  );
}

Future<void> _cleanup(TenturaDb db) async {
  await db.customStatement('SELECT mr_reset()');
  await db.customStatement(
    "DELETE FROM public.polling_act WHERE polling_id = '$_poll'",
  );
  await db.customStatement(
    "DELETE FROM public.polling_variant WHERE polling_id = '$_poll'",
  );
  await db.customStatement("DELETE FROM public.polling WHERE id = '$_poll'");
  final list = _ids.map((i) => "'$i'").join(', ');
  await db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($list) OR object_user_id IN ($list)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($list) OR object IN ($list)',
  );
  await db.customStatement(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($list) OR object IN ($list)',
  );
  await db.customStatement('DELETE FROM public."user" WHERE id IN ($list)');
}
