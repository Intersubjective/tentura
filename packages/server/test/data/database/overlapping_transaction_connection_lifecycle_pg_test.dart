@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

const _shortLifetime = Duration(seconds: 1);
const _longLifetime = Duration(hours: 1);
const _lifetimeElapsed = Duration(milliseconds: 2500);

typedef _Backend = ({int pid, String transactionId});

Future<_Backend> _backend(TenturaDb database) async {
  final row = await database
      .customSelect(
        'SELECT pg_backend_pid() AS pid, '
        'txid_current()::text AS transaction_id',
      )
      .getSingle();
  return (
    pid: row.read<int>('pid'),
    transactionId: row.read<String>('transaction_id'),
  );
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OVERLAPPING_CONNECTION_LIFECYCLE_TEST_DB',
    defaultNamePrefix: 'tentura_test_overlap_lifecycle',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  Future<void> withPool(
    Future<void> Function(TenturaDb database) action, {
    Duration maxConnectionAge = _longLifetime,
    Duration maxSessionUse = _longLifetime,
    int connections = 1,
  }) async {
    final pool = MainDbPool(
      _LifecycleEnv(
        target.databaseEnv,
        maxConnectionAge: maxConnectionAge,
        maxSessionUse: maxSessionUse,
        connections: connections,
      ),
    );
    final database = TenturaDb.scoped(pool);
    try {
      await action(database);
    } finally {
      await database.close();
      await pool.close();
    }
  }

  Future<bool> terminate(int pid) async {
    final terminated = await session.writer.execute(
      Sql.named('''
SELECT pg_terminate_backend(pid) AS terminated
FROM pg_stat_activity
WHERE datname = current_database() AND pid = @pid
'''),
      parameters: {'pid': pid},
    );
    return terminated.single.single == true;
  }

  for (final connections in [1, 2]) {
    test(
      'an idle pooled backend terminated between transactions is replaced '
      'for the next transaction ($connections connection(s))',
      () async {
        final pool = MainDbPool(
          _LifecycleEnv(
            target.databaseEnv,
            maxConnectionAge: _longLifetime,
            maxSessionUse: _longLifetime,
            connections: connections,
          ),
        );
        final database = TenturaDb.scoped(pool);
        try {
          final killed = await database.transaction(() => _backend(database));
          // Take the pool's own handle on that idle connection, so the test
          // can wait until the client has seen the server close it.
          late Connection idle;
          final idlePid = await pool.pool.withConnection((connection) async {
            idle = connection;
            final rows = await connection.execute('SELECT pg_backend_pid()');
            return rows.single.single! as int;
          });
          expect(idlePid, killed.pid, reason: 'The idle connection is reused.');

          expect(await terminate(killed.pid), isTrue);
          await idle.closed.timeout(kStableStateWait);

          final recovered = await database.transaction(
            () => _backend(database),
          );
          expect(
            recovered.pid,
            isNot(killed.pid),
            reason: 'A dead idle connection must not be handed out again.',
          );
        } finally {
          await database.close();
          await pool.close();
        }
      },
    );
  }

  group(
    'Connection recycling while transactions overlap on two connections',
    () {
      test(
        'connection age rotates every connection although a transaction is '
        'open at every moment',
        () => withPool(
          _expectRotationUnderSteadyOverlap,
          maxConnectionAge: _shortLifetime,
          connections: 2,
        ),
      );

      test(
        'session use rotates every connection although a transaction is '
        'open at every moment',
        () => withPool(
          _expectRotationUnderSteadyOverlap,
          maxSessionUse: _shortLifetime,
          connections: 2,
        ),
      );

      test(
        'a terminated backend fails only its own transaction and is '
        'replaced while another transaction stays open',
        () => withPool(connections: 2, (database) async {
          final victim = _HeldTransaction(database);
          final bystander = _HeldTransaction(database);
          _HeldTransaction? next;
          try {
            final killed = await victim.entered.future.timeout(
              kStableStateWait,
            );
            final open = await bystander.entered.future.timeout(
              kStableStateWait,
            );
            expect(open.pid, isNot(killed.pid));

            expect(await terminate(killed.pid), isTrue);
            await victim.finish();
            expect(victim.error, isNotNull);

            // The bystander still holds its transaction, so the open
            // transactions never drain while the victim is replaced.
            next = _HeldTransaction(database);
            final recovered = await next.entered.future.timeout(
              kStableStateWait,
            );
            expect(recovered.pid, isNot(anyOf(killed.pid, open.pid)));

            await bystander.finish();
            await next.finish();
          } finally {
            await victim.finish();
            await bystander.finish();
            await next?.finish();
          }
          bystander.checkSuccess();
          next.checkSuccess();
        }),
      );
    },
  );

  group('Connection recycling with overlapping transactions', () {
    test(
      'connection age rotates between transactions while other '
      'transactions are queued',
      () => withPool(
        _expectRotationWhileOverlapped,
        maxConnectionAge: _shortLifetime,
      ),
    );

    test(
      'session use rotates between transactions while other '
      'transactions are queued',
      () => withPool(
        _expectRotationWhileOverlapped,
        maxSessionUse: _shortLifetime,
      ),
    );

    test(
      'a terminated backend is replaced for the next queued transaction',
      () => withPool((database) async {
        final victim = _HeldTransaction(database);
        _HeldTransaction? next;
        _HeldTransaction? tail;
        try {
          final killed = await victim.entered.future.timeout(kStableStateWait);
          // Both successors are submitted before the failing transaction ends.
          // A pin shared by overlapping transaction futures never drains here.
          next = _HeldTransaction(database);
          tail = _HeldTransaction(database);
          expect(next.entered.isCompleted, isFalse);
          expect(tail.entered.isCompleted, isFalse);

          final terminated = await session.writer.execute(
            Sql.named('''
SELECT pg_terminate_backend(pid) AS terminated
FROM pg_stat_activity
WHERE datname = current_database() AND pid = @pid
'''),
            parameters: {'pid': killed.pid},
          );
          expect(terminated.single.single, isTrue);
          // The victim's final statement must fail. Recovery belongs to the
          // next transaction, not a retry of the interrupted transaction.
          await victim.finish();
          expect(
            victim.error,
            isNotNull,
            reason:
                'Terminating the backend must fail the interrupted transaction.',
          );

          final recovered = await next.entered.future.timeout(kStableStateWait);
          expect(recovered.pid, isNot(killed.pid));
          expect(
            recovered.transactionId,
            isNot(killed.transactionId),
            reason:
                'Recovery must start a new transaction on the replacement backend.',
          );
          expect(
            tail.entered.isCompleted,
            isFalse,
            reason:
                'The tail must remain queued while the recovered transaction is held.',
          );

          await next.finish();
          expect(
            next.error,
            isNull,
            reason:
                'The recovered transaction must complete its final statement and commit.',
          );

          await tail.entered.future.timeout(kStableStateWait);
          await tail.finish();
          expect(
            tail.error,
            isNull,
            reason:
                'The queued tail must also complete on a usable connection.',
          );
        } finally {
          await victim.finish();
          await next?.finish();
          await tail?.finish();
        }
        next.checkSuccess();
        tail.checkSuccess();
      }),
    );
  });
}

/// Two transactions overlap on two connections; each one that ends is
/// replaced by a queued successor before the other ends, so the set of open
/// transactions never empties. Each aged connection must still be replaced.
Future<void> _expectRotationUnderSteadyOverlap(TenturaDb database) async {
  final first = _HeldTransaction(database);
  final second = _HeldTransaction(database);
  _HeldTransaction? third;
  _HeldTransaction? fourth;
  try {
    final a = await first.entered.future.timeout(kStableStateWait);
    final b = await second.entered.future.timeout(kStableStateWait);
    expect(b.pid, isNot(a.pid), reason: 'Both transactions are concurrent.');
    // Age both leases before queueing successors, as in the queued case.
    await Future<void>.delayed(_lifetimeElapsed);

    third = _HeldTransaction(database);
    expect(third.entered.isCompleted, isFalse);
    await first.finish();
    first.checkSuccess();
    final c = await third.entered.future.timeout(kStableStateWait);
    expect(c.pid, isNot(anyOf(a.pid, b.pid)));

    fourth = _HeldTransaction(database);
    expect(fourth.entered.isCompleted, isFalse);
    await second.finish();
    second.checkSuccess();
    final d = await fourth.entered.future.timeout(kStableStateWait);
    expect(
      d.pid,
      isNot(anyOf(a.pid, b.pid, c.pid)),
      reason: 'The second aged connection must be replaced as well.',
    );
  } finally {
    await first.finish();
    await second.finish();
    await third?.finish();
    await fourth?.finish();
  }
  third.checkSuccess();
  fourth.checkSuccess();
}

Future<void> _expectRotationWhileOverlapped(TenturaDb database) async {
  final first = _HeldTransaction(database);
  _HeldTransaction? next;
  _HeldTransaction? tail;
  try {
    final expired = await first.entered.future.timeout(kStableStateWait);
    // Age the held lease before queueing successors so the interactive
    // admission deadline does not expire while waiting for the lifetime limit.
    await Future<void>.delayed(_lifetimeElapsed);
    next = _HeldTransaction(database);
    tail = _HeldTransaction(database);
    expect(next.entered.isCompleted, isFalse);
    expect(tail.entered.isCompleted, isFalse);
    await first.finish();
    first.checkSuccess();

    final replacement = await next.entered.future.timeout(kStableStateWait);
    expect(
      replacement.pid,
      isNot(expired.pid),
      reason:
          'Recycling must not wait for every overlapping transaction to end.',
    );
    expect(tail.entered.isCompleted, isFalse);
  } finally {
    await first.finish();
    await next?.finish();
    await tail?.finish();
  }
  first.checkSuccess();
  next.checkSuccess();
  tail.checkSuccess();
}

class _HeldTransaction {
  _HeldTransaction(TenturaDb database) {
    // A queued transaction may fail before its entered future is awaited.
    entered.future.ignore();
    _done = database
        .transaction(() async {
          final before = await _backend(database);
          entered.complete(before);
          await release.future;
          expect(
            await _backend(database),
            before,
            reason:
                'A connection must remain unchanged within an active transaction.',
          );
        })
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _error = error;
            _stackTrace = stackTrace;
            if (!entered.isCompleted) entered.completeError(error, stackTrace);
          },
        );
  }

  final entered = Completer<_Backend>();
  final release = Completer<void>();
  late final Future<void> _done;
  Object? _error;
  late final StackTrace _stackTrace;

  Object? get error => _error;

  Future<void> finish() async {
    if (!release.isCompleted) release.complete();
    await _done.timeout(kCompletionWait);
  }

  void checkSuccess() {
    if (_error != null) Error.throwWithStackTrace(_error!, _stackTrace);
  }
}

class _LifecycleEnv extends Env {
  _LifecycleEnv(
    Env postgres, {
    required Duration maxConnectionAge,
    required Duration maxSessionUse,
    required int connections,
  }) : pgPoolSettings = PoolSettings(
         maxConnectionCount: connections,
         maxConnectionAge: maxConnectionAge,
         maxSessionUse: maxSessionUse,
         connectTimeout: kStableStateWait,
         sslMode: postgres.pgEndpointSettings.sslMode,
       ),
       super(
         environment: Environment.test,
         printEnv: false,
         isDebugModeOn: false,
         pgHost: postgres.pgHost,
         pgPort: postgres.pgPort,
         pgDatabase: postgres.pgDatabase,
         pgUsername: postgres.pgUsername,
         pgPassword: postgres.pgPassword,
         maxConnectionCount: connections,
       );

  @override
  // Keep age and session-use limits independent so each test proves its limit.
  // ignore: overridden_fields
  final PoolSettings pgPoolSettings;
}
