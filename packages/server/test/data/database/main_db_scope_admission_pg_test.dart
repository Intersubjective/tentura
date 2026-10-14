@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/session_repository.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

const _viewer = 'Uscopeviewer1';
const _context = 'scope-admission';
const _mainSlots = 4;
const _maxWaiting = 32;
const _interactiveObservation = Duration(milliseconds: 500);
const _fullObservation = Duration(milliseconds: 1300);

Future<void> main() async {
  // This portable guard remains runnable when the PG cases are skipped. It
  // checks production configuration, not the test harness's pool override.
  test('main pool capacity is available without the transaction spike', () {
    final env = Env(
      environment: Environment.test,
      printEnv: false,
      maxConnectionCount: _mainSlots,
    );
    expect(
      env.pgPoolSettings.maxConnectionCount,
      _mainSlots,
      reason:
          'Scoped main DB access must honor the configured connection '
          'budget without DRIFT_TRANSACTION_PINNED_POOL_ENABLED.',
    );
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MAIN_DB_ADMISSION_TEST_DB',
    defaultNamePrefix: 'tentura_test_main_db_admission',
  );
  final unavailable = await pgSkipReason(target);
  final reachable = unavailable == null;
  late DisposablePgWriterSession session;
  late _Harness harness;

  setUpAll(() async {
    if (!reachable) return;
    session = await setUpDisposablePgWriter(target: target);
    await session.writer.execute('''
      INSERT INTO public."user"
        (id, display_name, public_key, created_at, updated_at)
      VALUES ('$_viewer', '$_viewer', 'pk-$_viewer', now(), now())
    ''');
    await session.writer.execute('''
      CREATE TABLE public.main_db_admission_probe (
        job integer PRIMARY KEY,
        actor text NOT NULL,
        backend_pid integer NOT NULL
      )
    ''');
  });

  setUp(() async {
    if (!reachable) return;
    await session.writer.execute('TRUNCATE public.main_db_admission_probe');
    // A valid empty visible-set cache makes these DB scheduling tests
    // independent of MeritRank RPC availability and cache-fill latency.
    await session.writer.execute('''
      INSERT INTO public.person_visible_set_cache
        (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
      SELECT '$_viewer', '$_context', e.epoch, g.generation, '{}'::text[]
      FROM public.mr_publish_epoch e
      CROSS JOIN public.visibility_trust_generation g
      WHERE e.id = true AND g.id = true
      ON CONFLICT (viewer_id, ctx) DO UPDATE SET
        mr_epoch = EXCLUDED.mr_epoch, trust_gen = EXCLUDED.trust_gen,
        peer_ids = EXCLUDED.peer_ids
    ''');
    harness = _Harness(target.databaseEnv, session.writer);
  });

  tearDown(() async {
    if (reachable) await harness.close();
  });

  tearDownAll(() async {
    if (reachable) await tearDownDisposablePgWriter(session: session);
  });

  group('Main database scope admission', () {
    test(
      'FULL and a short V2 mutation overlap after connection aging '
      'without losing nested transaction ownership',
      () async {
        final fullStarted = Completer<void>();
        final releaseFull = Completer<void>();
        _SessionProbe? before;
        _SessionProbe? after;
        final full = _observe(
          harness.full((database) async {
            before = await _sessionProbe(database);
            fullStarted.complete();
            await releaseFull.future;
            after = await database.transaction(
              () => _sessionProbe(database),
              requireNew: true,
            );
          }),
        );
        _Ticket? mutation;
        var overlapped = false;
        var simultaneousMainSessions = 0;
        try {
          await fullStarted.future.timeout(kStableStateWait);
          // The pool's connection age is one second. A nested savepoint
          // after this stall must still belong to the original transaction.
          await Future<void>.delayed(const Duration(milliseconds: 2500));
          mutation = _observe(harness.shortV2Mutation());
          overlapped = await _completesWithin(
            mutation.done,
            _interactiveObservation,
          );
          simultaneousMainSessions = harness.mainEnv.openConnections.length;
        } finally {
          _release(releaseFull);
          await full.done.timeout(kCompletionWait);
          await mutation?.done.timeout(kCompletionWait);
        }

        _expectSuccess(full);
        _expectSuccess(mutation);
        expect(
          overlapped,
          isTrue,
          reason:
              'A FULL snapshot must not own the executor lock used by '
              'a short constellation anchor mutation.',
        );
        expect(simultaneousMainSessions, greaterThanOrEqualTo(2));
        expect(simultaneousMainSessions, lessThanOrEqualTo(_mainSlots));
        expect(
          after,
          before,
          reason:
              'Nested SAVEPOINT must not raise 25P01 '
              'or switch PostgreSQL sessions after connection aging.',
        );
      },
    );

    test(
      'mixed FULL and mutation overload keeps at most 32 waiters, '
      'refuses promptly, bounds RSS, and preserves auth latency',
      () async {
        final authWarmup = Stopwatch()..start();
        expect(
          await harness.auth.findActiveByTokenHash('missing-session'),
          isNull,
        );
        authWarmup.stop();
        final held = await harness.holdMainSlots();
        final tickets = <_Ticket>[];
        const offered = 512;
        const payloadBytes = 256 * 1024;
        final baselineRss = ProcessInfo.currentRss;
        var peakRss = baselineRss;
        var executedMutations = 0;
        var fastRefusals = 0;
        var waiting = offered;
        var openMainSessions = 0;
        var worstAuthLatency = Duration.zero;
        try {
          for (var index = 0; index < offered; index++) {
            if (index % 16 == 0) {
              tickets.add(_observe(harness.full((_) async {})));
            } else {
              // Rejected work must release its request payload. The test
              // keeps outcomes, not a separate reference to these buffers.
              final payload = Uint8List(payloadBytes)
                ..fillRange(0, payloadBytes, index % 255);
              tickets.add(
                _observe(
                  harness.mutations.run<void>(
                    actorUserId: 'burst-$index',
                    action: () async {
                      executedMutations++;
                      await harness.writeProbe(index, '${payload.first}');
                    },
                  ),
                ),
              );
            }
            if (index % 8 == 7) {
              await Future<void>.delayed(Duration.zero);
              final rss = ProcessInfo.currentRss;
              if (rss > peakRss) peakRss = rss;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          fastRefusals = tickets
              .where(
                (ticket) => ticket.completed && _isRetryRefusal(ticket.error),
              )
              .length;
          waiting = tickets.where((ticket) => !ticket.completed).length;
          openMainSessions = harness.mainEnv.openConnections.length;
          for (var index = 0; index < 16; index++) {
            final watch = Stopwatch()..start();
            expect(
              await harness.auth.findActiveByTokenHash('missing-$index'),
              isNull,
            );
            watch.stop();
            if (watch.elapsed > worstAuthLatency) {
              worstAuthLatency = watch.elapsed;
            }
          }
        } finally {
          held.releaseAll();
          await Future.wait([
            ...held.tickets.map((ticket) => ticket.done),
            ...tickets.map((ticket) => ticket.done),
          ]).timeout(kCompletionWait);
        }

        expect(fastRefusals, greaterThanOrEqualTo(offered - _maxWaiting));
        expect(waiting, lessThanOrEqualTo(_maxWaiting));
        expect(
          openMainSessions,
          _mainSlots,
          reason: 'Waiting work must not acquire another connection.',
        );
        expect(executedMutations, lessThanOrEqualTo(_maxWaiting));
        expect(
          peakRss - baselineRss,
          lessThan(64 * 1024 * 1024),
          reason:
              'A bounded queue must not retain the full 128 MiB burst '
              'of request payloads. The allowance includes VM overhead.',
        );
        expect(
          worstAuthLatency,
          lessThan(authWarmup.elapsed + _interactiveObservation),
          reason: 'Auth uses reserved capacity while the main DB is saturated.',
        );
        for (final ticket in tickets.where((ticket) => ticket.error != null)) {
          expect(ticket.error, predicate<Object?>(_isRetryRefusal));
        }
      },
    );

    test(
      'expired interactive and FULL waiters never run after a slot opens',
      () async {
        final held = await harness.holdMainSlots();
        var mutationStarted = false;
        var fullStarted = false;
        final mutation = _observe(
          harness.mutations.run<void>(
            actorUserId: 'expired-interactive',
            action: () async {
              mutationStarted = true;
              await harness.writeProbe(1, 'expired-interactive');
            },
          ),
        );
        final full = _observe(
          harness.full((_) async {
            fullStarted = true;
          }),
        );
        var interactiveExpired = false;
        var fullExpired = false;
        try {
          await Future<void>.delayed(_interactiveObservation);
          interactiveExpired =
              mutation.completed && _isRetryRefusal(mutation.error);
          await Future<void>.delayed(
            _fullObservation - _interactiveObservation,
          );
          fullExpired = full.completed && _isRetryRefusal(full.error);
        } finally {
          held.releaseAll();
          await Future.wait([
            ...held.tickets.map((ticket) => ticket.done),
            mutation.done,
            full.done,
          ]).timeout(kCompletionWait);
        }

        expect(
          interactiveExpired,
          isTrue,
          reason: 'Interactive queue budget is approximately 250 ms.',
        );
        expect(
          fullExpired,
          isTrue,
          reason: 'FULL queue budget is approximately one second.',
        );
        expect(mutationStarted, isFalse);
        expect(fullStarted, isFalse);
        final rows = await harness.writer.execute(
          'SELECT job FROM public.main_db_admission_probe',
        );
        expect(
          rows,
          isEmpty,
          reason: 'Expired work must not leave a database write.',
        );
      },
    );

    test('one actor cannot consume the shared waiting budget', () async {
      final held = await harness.holdMainSlots();
      final flood = [
        for (var index = 0; index < 16; index++)
          _observe(
            harness.mutations.run<void>(
              actorUserId: 'flooding-actor',
              action: () => harness.writeProbe(index, 'flooding-actor'),
            ),
          ),
      ];
      final otherActor = _observe(
        harness.mutations.run<void>(
          actorUserId: 'other-actor',
          action: () => harness.writeProbe(100, 'other-actor'),
        ),
      );
      var refusedForActor = 0;
      var otherActorCompleted = false;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // Seventeen offered scopes do not fill the global 32-slot queue.
        // Refusal here must therefore come from the per-user limit.
        refusedForActor = flood
            .where(
              (ticket) => ticket.completed && _isRetryRefusal(ticket.error),
            )
            .length;
        held.releaseOne();
        otherActorCompleted = await _completesWithin(
          otherActor.done,
          _interactiveObservation,
        );
      } finally {
        held.releaseAll();
        await Future.wait([
          ...held.tickets.map((ticket) => ticket.done),
          ...flood.map((ticket) => ticket.done),
          otherActor.done,
        ]).timeout(kCompletionWait);
      }

      expect(
        refusedForActor,
        greaterThan(0),
        reason:
            'Per-user admission must refuse a flood before it fills '
            'the worker-wide queue.',
      );
      expect(otherActorCompleted, isTrue);
      _expectSuccess(otherActor);
    });

    test(
      'visibility generation row contention leaves capacity for FULL, '
      'a short V2 mutation, and auth',
      () async {
        final generationBefore = await harness.generation();
        final fullStarted = Completer<void>();
        final releaseFull = Completer<void>();
        final generationHeld = Completer<void>();
        final releaseGeneration = Completer<void>();
        final full = _observe(
          harness.full((database) async {
            await _sessionProbe(database);
            fullStarted.complete();
            await releaseFull.future;
          }),
        );
        _Ticket? holder;
        _Ticket? contender;
        _Ticket? shortMutation;
        var shortMutationOverlapped = false;
        var authLatency = Duration.zero;
        try {
          await fullStarted.future.timeout(kStableStateWait);
          holder = _observe(
            harness.mutations.run<void>(
              actorUserId: 'generation-holder',
              action: () async {
                await harness.bumpGeneration();
                generationHeld.complete();
                await releaseGeneration.future;
              },
            ),
          );
          await generationHeld.future.timeout(kStableStateWait);
          final contenderPid = Completer<int>();
          contender = _observe(
            harness.mutations.run<void>(
              actorUserId: 'generation-contender',
              action: () async {
                contenderPid.complete(
                  (await _sessionProbe(harness.database)).pid,
                );
                await harness.bumpGeneration();
              },
            ),
          );
          final blockedPid = await contenderPid.future.timeout(
            kStableStateWait,
          );
          await _waitForGenerationLock(
            harness.writer,
            target.databaseName,
            blockedPid,
          );
          shortMutation = _observe(harness.shortV2Mutation());
          shortMutationOverlapped = await _completesWithin(
            shortMutation.done,
            _interactiveObservation,
          );
          final watch = Stopwatch()..start();
          expect(
            await harness.auth.findActiveByTokenHash('during-generation-lock'),
            isNull,
          );
          watch.stop();
          authLatency = watch.elapsed;
        } finally {
          _release(releaseGeneration);
          await holder?.done.timeout(kCompletionWait);
          await contender?.done.timeout(kCompletionWait);
          _release(releaseFull);
          await full.done.timeout(kCompletionWait);
          await shortMutation?.done.timeout(kCompletionWait);
        }

        [full, holder, contender, shortMutation].forEach(_expectSuccess);
        expect(
          shortMutationOverlapped,
          isTrue,
          reason:
              'The single m0235 visibility_trust_generation row may '
              'block one writer, but must not serialize unrelated scopes.',
        );
        expect(authLatency, lessThan(_interactiveObservation));
        expect(
          await harness.generation(),
          generationBefore + 2,
          reason: 'Both contending writes must commit without a lost bump.',
        );
        expect(
          harness.mainEnv.openConnections.length,
          lessThanOrEqualTo(_mainSlots),
        );
      },
    );
  }, skip: unavailable ?? false);
}

typedef _SessionProbe = ({int pid, String transactionStarted});

Future<_SessionProbe> _sessionProbe(TenturaDb database) async {
  final row = await database
      .customSelect(
        'SELECT pg_backend_pid() AS pid, now()::text AS transaction_started',
      )
      .getSingle();
  return (
    pid: row.read<int>('pid'),
    transactionStarted: row.read<String>('transaction_started'),
  );
}

Future<void> _waitForGenerationLock(
  Connection writer,
  String database,
  int pid,
) async {
  final deadline = DateTime.now().add(kStableStateWait);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      Sql.named('''
      SELECT 1 FROM pg_stat_activity
      WHERE datname = @database AND pid = @pid
        AND state = 'active' AND wait_event_type = 'Lock'
        AND query LIKE '%visibility_trust_generation%'
    '''),
      parameters: {'database': database, 'pid': pid},
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(
    'The second visibility generation update never reached its row-lock wait',
  );
}

final class _Harness {
  _Harness(Env postgres, this.writer)
    : mainEnv = _PoolEnv(postgres, connections: _mainSlots),
      authEnv = _PoolEnv(postgres, connections: 1) {
    database = TenturaDb(mainEnv);
    mutations = MutatingUnitOfWork(database);
    authDatabase = TenturaDb(authEnv);
    auth = SessionRepository(authDatabase);
    anchors = ConstellationAnchorRepository(database);
  }

  final Connection writer;
  final _PoolEnv mainEnv;
  final _PoolEnv authEnv;
  late final TenturaDb database;
  late final TenturaDb authDatabase;
  late final MutatingUnitOfWorkPort mutations;
  late final SessionRepository auth;
  late final ConstellationAnchorRepository anchors;

  Future<void> shortV2Mutation() async {
    // Even an empty batch owns an actor transaction and initializes the
    // viewer cursor, exercising the real V2 repository boundary.
    await anchors.applyBatch(viewerId: _viewer, ops: const []);
  }

  Future<ConstellationFieldSnapshot> full(
    Future<void> Function(TenturaDb) probe,
  ) =>
      ConstellationFieldRepository(
        database,
        const _EmptyProfiles(),
        snapshotOpenProbe: probe,
      ).readSnapshot(
        viewerId: _viewer,
        context: _context,
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      );

  Future<void> writeProbe(int job, String actor) => database.customStatement(
    r'INSERT INTO public.main_db_admission_probe VALUES ($1, $2, pg_backend_pid())',
    [job, actor],
  );

  Future<void> bumpGeneration() => database.customStatement(
    'UPDATE public.visibility_trust_generation '
    'SET generation = generation + 1 WHERE id = true',
  );

  Future<int> generation() async =>
      (await writer.execute(
            'SELECT generation FROM public.visibility_trust_generation WHERE id = true',
          )).single.single!
          as int;

  Future<_HeldSlots> holdMainSlots() async {
    final gates = [
      for (var index = 0; index < _mainSlots; index++) Completer<void>(),
    ];
    final entered = [
      for (var index = 0; index < _mainSlots; index++) Completer<void>(),
    ];
    final tickets = [
      for (var index = 0; index < _mainSlots; index++)
        _observe(
          mutations.run<void>(
            actorUserId: 'slot-holder-$index',
            action: () async {
              await _sessionProbe(database);
              entered[index].complete();
              await gates[index].future;
            },
          ),
        ),
    ];
    try {
      await Future.wait(
        entered.map((gate) => gate.future),
      ).timeout(kStableStateWait);
    } on Object {
      gates.forEach(_release);
      await Future.wait(
        tickets.map((ticket) => ticket.done),
      ).timeout(kCompletionWait);
      rethrow;
    }
    return _HeldSlots(gates, tickets);
  }

  Future<void> close() async {
    await database.close();
    await authDatabase.close();
  }
}

final class _PoolEnv extends Env {
  _PoolEnv(Env postgres, {required this.connections})
    : super(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: postgres.pgHost,
        pgPort: postgres.pgPort,
        pgDatabase: postgres.pgDatabase,
        pgUsername: postgres.pgUsername,
        pgPassword: postgres.pgPassword,
        maxConnectionAge: 1,
        maxConnectionCount: connections,
      );

  final int connections;
  final _opened = <int, Connection>{};
  Map<int, Connection> get openConnections => {
    for (final entry in _opened.entries)
      if (entry.value.isOpen) entry.key: entry.value,
  };

  @override
  // Test-only pool budget: isolates scope migration from the legacy default
  // pool clamp, which the portable production-configuration test covers.
  // ignore: overridden_fields
  late final pgPoolSettings = PoolSettings(
    maxConnectionCount: connections,
    maxConnectionAge: const Duration(seconds: 1),
    maxSessionUse: const Duration(hours: 1),
    connectTimeout: const Duration(seconds: 5),
    sslMode: SslMode.disable,
    onOpen: (connection) async {
      await connection.execute('SET statement_timeout = 15000');
      final pid =
          (await connection.execute('SELECT pg_backend_pid()')).single.single!
              as int;
      _opened[pid] = connection;
    },
  );
}

final class _HeldSlots {
  const _HeldSlots(this.gates, this.tickets);
  final List<Completer<void>> gates;
  final List<_Ticket> tickets;
  void releaseOne() => _release(gates.first);
  void releaseAll() => gates.forEach(_release);
}

final class _Ticket {
  late Future<void> done;
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;
}

_Ticket _observe(Future<Object?> action) {
  final ticket = _Ticket();
  ticket.done = action.then<void>(
    (_) {
      ticket.completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      ticket
        ..error = error
        ..stackTrace = stackTrace
        ..completed = true;
    },
  );
  return ticket;
}

void _expectSuccess(_Ticket ticket) {
  if (ticket.error != null) {
    Error.throwWithStackTrace(ticket.error!, ticket.stackTrace!);
  }
  expect(ticket.completed, isTrue);
}

bool _isRetryRefusal(Object? error) =>
    error is RateLimitedException ||
    error is ConstellationException &&
        error.code is ConstellationExceptionCodes &&
        (error.code as ConstellationExceptionCodes).exceptionCode ==
            ConstellationExceptionCode.retryLater;

Future<bool> _completesWithin(Future<void> future, Duration budget) =>
    Future.any([
      future.then((_) => true),
      Future<bool>.delayed(budget, () => false),
    ]);

void _release(Completer<void> gate) {
  if (!gate.isCompleted) gate.complete();
}

final class _EmptyProfiles implements UserProfileBatchLookup {
  const _EmptyProfiles();
  @override
  Future<Map<String, ConstellationPeerRecord>> constellationProfilesByIds(
    Iterable<String> ids,
  ) async => {};
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {};
  @override
  Future<Map<String, UserPublicRecord>> userPublicRecordsByIds({
    required Iterable<String> ids,
    required Set<String> reciprocalPeerIds,
    Set<String> trustsViewerPeerIds = const {},
    Set<String> viewerTrustsPeerIds = const {},
    Map<String, MutualScoreRecord> scoresByPeerId = const {},
  }) async => {};
}
