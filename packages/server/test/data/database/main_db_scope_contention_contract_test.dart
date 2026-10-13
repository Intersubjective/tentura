@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/session_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';

const _viewer = 'Udbcontract1';
const _context = 'main-db-contention';
const _slots = 4;
const _maxWaiting = 32;
const _interactiveObservation = Duration(milliseconds: 500);
const _fullObservation = Duration(milliseconds: 1300);

Future<void> main() async {
  group('Main database scope ownership', () {
    test('configured concurrency does not require a transaction spike', () {
      final env = Env(
        environment: Environment.test,
        printEnv: false,
        maxConnectionCount: _slots,
      );
      expect(env.pgPoolSettings.maxConnectionCount, _slots);
    });

    test('scoped executors retire the pinning shim and spike selector', () {
      final database = File(
        'lib/data/database/tentura_db.dart',
      ).readAsStringSync();
      final declarations = RegExp(
        r'\bclass\s+(_PinnedPoolSession|_TransactionPinnedPgDatabase|'
        r'_TransactionPinnedDelegate|_PinnedTransactionDelegate)\b',
      );
      final productionSources = Directory('lib/data/database')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => _isSource(file.path));
      expect(
        [
          for (final file in productionSources)
            if (declarations.hasMatch(file.readAsStringSync())) file.path,
        ],
        isEmpty,
        reason: 'Each scope must own its executor and connection lease.',
      );
      expect(
        RegExp(
          r'@override\s+Future<[^>]+>\s+transaction<[^>]+>\s*\(',
        ).hasMatch(database),
        isFalse,
        reason: 'Drift must own BEGIN, SAVEPOINT, COMMIT, and ROLLBACK.',
      );
      expect(
        RegExp(
          r'^\s*@(?:singleton|Singleton)\b',
          multiLine: true,
        ).hasMatch(database),
        isFalse,
        reason: 'Independent requests must not share a singleton executor.',
      );
      expect(
        File('lib/env.dart').readAsStringSync(),
        isNot(
          matches(
            r'\b(?:driftTransactionPinnedPoolEnabled|'
            r'DRIFT_TRANSACTION_PINNED_POOL_ENABLED)\b',
          ),
        ),
        reason:
            'The completed scope migration must remove the experimental '
            'selector, including its constructor argument and public field.',
      );
    });
  });

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MAIN_DB_CONTENTION_CONTRACT_TEST_DB',
    defaultNamePrefix: 'tentura_test_main_db_contract',
  );
  final unavailable = await pgSkipReason(target);
  late DisposablePgWriterSession session;
  late _Harness harness;

  group(
    'Shared main database admission under contention',
    () {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        await session.writer.execute('''
        INSERT INTO public."user"
          (id, display_name, public_key, created_at, updated_at)
        VALUES ('$_viewer', '$_viewer', 'pk-$_viewer', now(), now())
      ''');
        await session.writer.execute('''
        CREATE TABLE public.main_scope_contract_probe (
          job integer PRIMARY KEY,
          actor text NOT NULL,
          backend_pid integer NOT NULL
        )
      ''');
      });

      tearDownAll(() async {
        await session.writer.close();
        await target.drop();
      });

      setUp(() async {
        await session.writer.execute(
          'TRUNCATE public.main_scope_contract_probe',
        );
        // This suite measures DB ownership, not MeritRank. An authoritative
        // empty visible set avoids RPCs while exercising the real FULL reader.
        await session.writer.execute('''
        INSERT INTO public.person_visible_set_cache
          (viewer_id, ctx, mr_epoch, trust_gen, peer_ids)
        SELECT '$_viewer', '$_context', e.epoch, g.generation, ARRAY[]::text[]
        FROM public.mr_publish_epoch e
        CROSS JOIN public.visibility_trust_generation g
        WHERE e.id AND g.id
        ON CONFLICT (viewer_id, ctx) DO UPDATE SET
          mr_epoch = EXCLUDED.mr_epoch,
          trust_gen = EXCLUDED.trust_gen,
          peer_ids = EXCLUDED.peer_ids
      ''');
        harness = _Harness(target.databaseEnv, session.writer);
      });

      tearDown(() => harness.close());

      test(
        'FULL and an anchor mutation overlap on different backends while '
        'nested savepoints survive connection aging',
        () async {
          final entered = Completer<void>();
          final aged = Completer<void>();
          final releaseFull = Completer<void>();
          _Probe? before;
          _Probe? after;
          _Outcome? mutation;
          final full = _observe(
            harness.full((database) async {
              before = await _probe(database);
              entered.complete();
              await Future<void>.delayed(const Duration(milliseconds: 2500));
              await database.transaction(() async {
                after = await _probe(database);
              }, requireNew: true);
              aged.complete();
              await releaseFull.future;
            }),
          );
          var overlapped = false;
          var activeMainConnections = 0;
          try {
            await entered.future.timeout(kStableStateWait);
            await aged.future.timeout(kStableStateWait);
            mutation = _observe(harness.shortMutation());
            overlapped = await _completesWithin(
              mutation.done,
              _interactiveObservation,
            );
            activeMainConnections = harness.mainEnv.liveConnections.length;
          } finally {
            _release(releaseFull);
            await _drain([full, ?mutation]);
          }
          _expectSuccess(full);
          _expectSuccess(mutation);
          expect(overlapped, isTrue);
          expect(activeMainConnections, inInclusiveRange(2, _slots));
          expect(
            after,
            before,
            reason:
                'Aged connections must preserve transaction and backend '
                'ownership without a 25P01 SAVEPOINT failure.',
          );
          final anchorRows = await session.writer.execute('''
          SELECT revision FROM public.constellation_anchor_cursor
          WHERE viewer_id = '$_viewer'
        ''');
          expect(anchorRows, hasLength(1));
        },
      );

      test(
        'a mixed FULL and mutation burst has bounded waiting and RSS, '
        'fast retry refusals, and stable auth latency',
        () async {
          final warmup = Stopwatch()..start();
          expect(await harness.auth.findActiveByTokenHash('warmup'), isNull);
          warmup.stop();
          final held = await harness.holdSlots();
          const offered = 512;
          const payloadBytes = 256 * 1024;
          final outcomes = <_Outcome>[];
          final baselineRss = ProcessInfo.currentRss;
          var peakRss = baselineRss;
          var peakQueued = 0;
          var refused = 0;
          var waiting = offered;
          var connections = 0;
          var worstAuth = Duration.zero;
          try {
            for (var index = 0; index < offered; index++) {
              outcomes.add(
                _observe(
                  index % 16 == 0
                      ? harness.full((_) async {})
                      : harness.payloadMutation(
                          index,
                          Uint8List(payloadBytes)
                            ..fillRange(0, payloadBytes, index % 255),
                        ),
                ),
              );
              final queued = harness.pool.admission.queued;
              if (queued > peakQueued) peakQueued = queued;
              if (index % 8 == 7) {
                await Future<void>.delayed(Duration.zero);
                final rss = ProcessInfo.currentRss;
                if (rss > peakRss) peakRss = rss;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
            refused = outcomes.where(_isRefused).length;
            waiting = outcomes.where((outcome) => !outcome.completed).length;
            connections = harness.mainEnv.liveConnections.length;
            for (var index = 0; index < 16; index++) {
              final watch = Stopwatch()..start();
              expect(
                await harness.auth.findActiveByTokenHash('burst-$index'),
                isNull,
              );
              watch.stop();
              if (watch.elapsed > worstAuth) worstAuth = watch.elapsed;
            }
          } finally {
            held.releaseAll();
            await _drain([...held.outcomes, ...outcomes]);
          }
          expect(peakQueued, lessThanOrEqualTo(_maxWaiting));
          expect(waiting, lessThanOrEqualTo(_maxWaiting));
          expect(refused, greaterThanOrEqualTo(offered - _maxWaiting));
          expect(connections, _slots);
          expect(harness.executedMutations, lessThanOrEqualTo(_maxWaiting));
          expect(
            peakRss - baselineRss,
            lessThan(64 * 1024 * 1024),
            reason: 'Refused work must release the burst of request payloads.',
          );
          expect(worstAuth, lessThan(warmup.elapsed + _interactiveObservation));
          for (final outcome in outcomes.where((item) => item.error != null)) {
            expect(_isRefused(outcome), isTrue, reason: '${outcome.error}');
          }
        },
      );

      test(
        'expired interactive and FULL scopes are refused before release '
        'and never execute SQL afterward',
        () async {
          final held = await harness.holdSlots();
          var fullStarted = false;
          final mutation = _observe(
            harness.payloadMutation(1001, Uint8List(1)),
          );
          final full = _observe(
            harness.full((_) async => fullStarted = true),
          );
          var interactiveExpired = false;
          var fullExpired = false;
          var queuedAfterExpiry = -1;
          try {
            await Future<void>.delayed(_interactiveObservation);
            interactiveExpired = _isRefused(mutation);
            await Future<void>.delayed(
              _fullObservation - _interactiveObservation,
            );
            fullExpired = _isRefused(full);
            queuedAfterExpiry = harness.pool.admission.queued;
          } finally {
            held.releaseAll();
            await _drain([...held.outcomes, mutation, full]);
          }
          expect(
            interactiveExpired,
            isTrue,
            reason: 'Interactive budget: 250 ms.',
          );
          expect(fullExpired, isTrue, reason: 'FULL budget: about one second.');
          expect(queuedAfterExpiry, 0);
          expect(harness.executedMutations, 0);
          expect(fullStarted, isFalse);
          expect(
            await session.writer.execute(
              'SELECT job FROM public.main_scope_contract_probe',
            ),
            isEmpty,
          );
        },
      );

      test('one actor cannot monopolize the shared waiting budget', () async {
        final held = await harness.holdSlots();
        final flood = [
          for (var index = 0; index < 16; index++)
            _observe(harness.write(index, 'flooding-actor')),
        ];
        final otherActor = _observe(harness.write(1000, 'other-actor'));
        var actorRefusals = 0;
        var otherActorAdmitted = false;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          actorRefusals = flood.where(_isRefused).length;
          held.releaseOne();
          otherActorAdmitted = await _completesWithin(
            otherActor.done,
            _interactiveObservation,
          );
        } finally {
          held.releaseAll();
          await _drain([...held.outcomes, ...flood, otherActor]);
        }
        expect(
          actorRefusals,
          greaterThan(0),
          reason: 'Seventeen requests do not fill the global 32-waiter limit.',
        );
        expect(otherActorAdmitted, isTrue);
        _expectSuccess(otherActor);
      });

      test(
        'visibility generation row contention preserves FULL, unrelated '
        'mutation, and auth capacity without losing generation increments',
        () async {
          final generationBefore = await harness.generation();
          final fullEntered = Completer<void>();
          final releaseFull = Completer<void>();
          final generationHeld = Completer<void>();
          final releaseGeneration = Completer<void>();
          final full = _observe(
            harness.full((database) async {
              await _probe(database);
              fullEntered.complete();
              await releaseFull.future;
            }),
          );
          _Outcome? holder;
          _Outcome? contender;
          _Outcome? shortMutation;
          var overlapped = false;
          var authLatency = Duration.zero;
          try {
            await fullEntered.future.timeout(kStableStateWait);
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
                  contenderPid.complete((await _probe(harness.writerDb)).pid);
                  await harness.bumpGeneration();
                },
              ),
            );
            await _waitForGenerationLock(
              session.writer,
              target.databaseName,
              await contenderPid.future.timeout(kStableStateWait),
            );
            shortMutation = _observe(harness.shortMutation());
            overlapped = await _completesWithin(
              shortMutation.done,
              _interactiveObservation,
            );
            final watch = Stopwatch()..start();
            expect(
              await harness.auth.findActiveByTokenHash('generation-contention'),
              isNull,
            );
            watch.stop();
            authLatency = watch.elapsed;
          } finally {
            _release(releaseGeneration);
            await _drain([
              ?holder,
              ?contender,
            ]);
            _release(releaseFull);
            await _drain([full, ?shortMutation]);
          }
          [full, holder, contender, shortMutation].forEach(_expectSuccess);
          expect(overlapped, isTrue);
          expect(authLatency, lessThan(_interactiveObservation));
          expect(await harness.generation(), generationBefore + 2);
          expect(
            harness.mainEnv.liveConnections.length,
            lessThanOrEqualTo(_slots),
          );
        },
      );
    },
    tags: ['pg'],
    skip: unavailable ?? false,
  );
}

typedef _Probe = ({int pid, String transactionStart});

Future<_Probe> _probe(TenturaDb database) async {
  final row = await database
      .customSelect('SELECT pg_backend_pid() AS pid, now()::text AS tx_start')
      .getSingle();
  return (
    pid: row.read<int>('pid'),
    transactionStart: row.read<String>('tx_start'),
  );
}

Future<void> _waitForGenerationLock(
  Connection writer,
  String databaseName,
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
      parameters: {'database': databaseName, 'pid': pid},
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('The generation contender never reached its PostgreSQL row-lock wait');
}

final class _Harness {
  _Harness(Env postgres, this.writer)
    : mainEnv = _PoolEnv(postgres, _slots),
      authEnv = _PoolEnv(postgres, 1) {
    pool = MainDbPool(mainEnv);
    readerDb = TenturaDb.scoped(pool);
    writerDb = TenturaDb.scoped(pool);
    anchorDb = TenturaDb.scoped(pool);
    authDb = TenturaDb.auth(authEnv);
    mutations = MutatingUnitOfWork(writerDb);
    anchors = ConstellationAnchorRepository(anchorDb);
    auth = SessionRepository(authDb);
  }

  final Connection writer;
  final _PoolEnv mainEnv;
  final _PoolEnv authEnv;
  late final MainDbPool pool;
  late final TenturaDb readerDb;
  late final TenturaDb writerDb;
  late final TenturaDb anchorDb;
  late final TenturaDb authDb;
  late final MutatingUnitOfWork mutations;
  late final ConstellationAnchorRepository anchors;
  late final SessionRepository auth;
  int executedMutations = 0;

  Future<ConstellationFieldSnapshot> full(
    Future<void> Function(TenturaDb) probe,
  ) =>
      ConstellationFieldRepository(
        readerDb,
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

  Future<void> shortMutation() async {
    await anchors.applyBatch(viewerId: _viewer, ops: const []);
  }

  Future<void> write(int job, String actor) => mutations.run<void>(
    actorUserId: actor,
    action: () => writerDb.customStatement(
      r'INSERT INTO public.main_scope_contract_probe VALUES ($1, $2, pg_backend_pid())',
      [job, actor],
    ),
  );

  Future<void> payloadMutation(
    int job,
    Uint8List payload,
  ) => mutations.run<void>(
    actorUserId: 'burst-$job',
    action: () async {
      executedMutations++;
      await writerDb.customStatement(
        r'INSERT INTO public.main_scope_contract_probe VALUES ($1, $2, pg_backend_pid())',
        [job, '${payload.first}'],
      );
    },
  );

  Future<void> bumpGeneration() => writerDb.customStatement(
    'UPDATE public.visibility_trust_generation '
    'SET generation = generation + 1 WHERE id = true',
  );

  Future<int> generation() async =>
      (await writer.execute(
            'SELECT generation FROM public.visibility_trust_generation WHERE id = true',
          )).single.single!
          as int;

  Future<_HeldSlots> holdSlots() async {
    final releases = [
      for (var index = 0; index < _slots; index++) Completer<void>(),
    ];
    final entered = [
      for (var index = 0; index < _slots; index++) Completer<void>(),
    ];
    final outcomes = [
      for (var index = 0; index < _slots; index++)
        _observe(
          mutations.run<void>(
            actorUserId: 'holder-$index',
            action: () async {
              await _probe(writerDb);
              entered[index].complete();
              await releases[index].future;
            },
          ),
        ),
    ];
    try {
      await Future.wait(
        entered.map((gate) => gate.future),
      ).timeout(kStableStateWait);
    } on Object {
      releases.forEach(_release);
      await _drain(outcomes);
      rethrow;
    }
    return _HeldSlots(releases, outcomes);
  }

  Future<void> close() async {
    await readerDb.close();
    await writerDb.close();
    await anchorDb.close();
    await authDb.close();
    await pool.close();
  }
}

final class _PoolEnv extends Env {
  _PoolEnv(Env postgres, this.connections)
    : super(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: postgres.pgHost,
        pgPort: postgres.pgPort,
        pgDatabase: postgres.pgDatabase,
        pgUsername: postgres.pgUsername,
        pgPassword: postgres.pgPassword,
        maxConnectionCount: connections,
        maxConnectionAge: 1,
      );

  final int connections;
  final _opened = <int, Connection>{};
  Map<int, Connection> get liveConnections => {
    for (final entry in _opened.entries)
      if (entry.value.isOpen) entry.key: entry.value,
  };

  @override
  // Keep the harness budget explicit; the portable test checks production
  // Env separately. onOpen records only this pool's sessions.
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
  const _HeldSlots(this.releases, this.outcomes);
  final List<Completer<void>> releases;
  final List<_Outcome> outcomes;
  void releaseOne() => _release(releases.first);
  void releaseAll() => releases.forEach(_release);
}

final class _Outcome {
  late Future<void> done;
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;
}

_Outcome _observe(Future<Object?> future) {
  final outcome = _Outcome();
  outcome.done = future.then<void>(
    (_) => outcome.completed = true,
    onError: (Object error, StackTrace stackTrace) {
      outcome
        ..error = error
        ..stackTrace = stackTrace
        ..completed = true;
    },
  );
  return outcome;
}

bool _isRefused(_Outcome outcome) =>
    outcome.completed &&
    (outcome.error is RateLimitedException ||
        outcome.error is ConstellationException &&
            (outcome.error! as ConstellationException).code
                is ConstellationExceptionCodes &&
            ((outcome.error! as ConstellationException).code
                        as ConstellationExceptionCodes)
                    .exceptionCode ==
                ConstellationExceptionCode.retryLater);

void _expectSuccess(_Outcome outcome) {
  if (outcome.error != null) {
    Error.throwWithStackTrace(outcome.error!, outcome.stackTrace!);
  }
  expect(outcome.completed, isTrue);
}

Future<void> _drain(Iterable<_Outcome> outcomes) => Future.wait(
  outcomes.map((outcome) => outcome.done),
).timeout(kCompletionWait);

Future<bool> _completesWithin(Future<void> future, Duration budget) =>
    Future.any([
      future.then((_) => true),
      Future<bool>.delayed(budget, () => false),
    ]);

void _release(Completer<void> gate) {
  if (!gate.isCompleted) gate.complete();
}

bool _isSource(String path) =>
    path.endsWith('.dart') &&
    ![
      '.g.dart',
      '.freezed.dart',
      '.gr.dart',
      '.config.dart',
      '.schema.dart',
    ].any(path.endsWith);

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
