// applyBatch contention gate (ARCH §4.4 / §7.6): 2/4/8 concurrent tabs of one
// viewer write through the production repository in both lock orders.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';

/// Gate thresholds at four tabs (plan U13): above either, the repository
/// switches to lock-first order.
const _exhaustionLimitPercent = 1.0;
const _wastedPreparationLimitPercent = 20.0;

/// Sustained writes per tab: alternating 1-op and 16-op batches.
const _callsPerTab = 30;
const _cascadeDeletes = 8;
const _cascadeSpacing = Duration(milliseconds: 25);

const _params = AnchorApplyParams(
  context: '',
  filters: ConstellationFieldMembershipFilters.defaults,
);

final class _Attempt {
  final Stopwatch clock = Stopwatch()..start();
  Duration? batchLockEnd;
  Duration? cursorLockStart;
}

final class _Stats {
  int attempted = 0;
  int committed = 0;
  int rolledBack = 0;
  int completedCalls = 0;
  int exhaustedCalls = 0;
  int acceptedOps = 0;
  Duration dbTime = Duration.zero;
  Duration preparationTime = Duration.zero;
  Duration wastedPreparation = Duration.zero;
  final callLatenciesMs = <double>[];
  final exhaustionErrors = <String>{};
}

/// Times each transaction attempt of one tab (one connection, so one
/// transaction at a time) and splits off its preparation: from the start (or,
/// in lock-first order, from the viewer batch lock) to the cursor lock.
/// Preparation of a rolled-back attempt is wasted.
final class _ContentionMeter extends QueryInterceptor {
  _ContentionMeter(this.stats);

  final _Stats stats;
  _Attempt? _attempt;

  static final _cursorLock = RegExp(
    r'constellation_anchor_cursor\s+WHERE\s+viewer_id\s*=\s*\$1\s+FOR UPDATE',
    caseSensitive: false,
  );

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    _attempt = _Attempt();
    stats.attempted++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    try {
      await super.commitTransaction(inner);
    } finally {
      _finish(committed: true);
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    try {
      await super.rollbackTransaction(inner);
    } finally {
      _finish(committed: false);
    }
  }

  void _finish({required bool committed}) {
    final attempt = _attempt;
    if (attempt == null) return;
    _attempt = null;
    final total = attempt.clock.elapsed;
    final preparation =
        (attempt.cursorLockStart ?? total) -
        (attempt.batchLockEnd ?? Duration.zero);
    stats.dbTime += total;
    stats.preparationTime += preparation;
    if (committed) {
      stats.committed++;
    } else {
      stats.rolledBack++;
      stats.wastedPreparation += preparation;
    }
  }

  Future<T> _observe<T>(String statement, Future<T> Function() run) async {
    final attempt = _attempt;
    if (attempt == null) return run();
    final isBatchLock = statement.contains('constellation_anchor_apply:');
    if (_cursorLock.hasMatch(statement)) {
      attempt.cursorLockStart ??= attempt.clock.elapsed;
    }
    final result = await run();
    if (isBatchLock) attempt.batchLockEnd = attempt.clock.elapsed;
    return result;
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _observe(statement, () => super.runCustom(executor, statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _observe(statement, () => super.runSelect(executor, statement, args));
}

final class _Profiles implements UserProfileBatchLookup {
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
  }) async => {
    for (final id in ids)
      id: UserPublicRecord(
        id: id,
        displayName: id,
        description: '',
        userAvailability: null,
      ),
  };
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

double _round(double v) => (v * 100).round() / 100;

Future<BigInt> _cursorRevision(Connection writer, String viewer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT revision FROM public.constellation_anchor_cursor '
      'WHERE viewer_id = @viewer',
    ),
    parameters: {'viewer': viewer},
  );
  return BigInt.from(rows.single.single! as int);
}

Future<int> _opLogRows(Connection writer, String viewer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*)::int FROM public.constellation_anchor_op_log '
      'WHERE viewer_id = @viewer',
    ),
    parameters: {'viewer': viewer},
  );
  return rows.single.single! as int;
}

void main() {
  late DisposablePgWriterSession session;
  late String viewer;
  late List<String> peers;
  const fixture = PerfFixture.denseTrust(visibleUsers: 1000);
  final reports = <String, Map<String, Object?>>{};
  var cascadeCursor = 0;

  setUpAll(() async {
    final target = DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_APPLY_BATCH_CONTENTION_TEST_DB',
      defaultNamePrefix: 'tentura_test_apply_batch_contention',
    );
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    final seed = await fixture.seed(session.writer);
    await requireNonEmptyMeritRankGraph(session.writer);
    viewer = seed.viewerId;
    final visible = await session.writer.execute(
      Sql.named(
        'SELECT peer_id FROM public.person_visible_peers_symmetric(@viewer, '
        "'') ORDER BY peer_id",
      ),
      parameters: {'viewer': viewer},
    );
    peers = [for (final row in visible) row.single! as String];
    expect(peers.length, greaterThan(64 + 12 * _cascadeDeletes));
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session);
  });

  Future<TenturaDb> openTab(_ContentionMeter meter) async {
    final target = session.target;
    return TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ).interceptWith(meter),
    );
  }

  List<AnchorApplyOp> batch(String prefix, List<String> targets, int seed) => [
    for (var i = 0; i < targets.length; i++)
      AnchorApplyOp(
        clientOpId: '$prefix-$i',
        kind: AnchorOpKind.upsert,
        target: ConstellationAnchorTarget.person(targets[i]),
        position: ConstellationAnchorPosition(
          xUnits: ((seed + i) % 9) - 4.0,
          yUnits: ((seed * 3 + i) % 9) - 4.0,
          coordinateSpaceVersion: 1,
        ),
      ),
  ];

  Future<Map<String, Object?>> run({
    required int tabs,
    required bool lockFirst,
    required bool cold,
  }) async {
    final order = lockFirst ? 'lock-first' : 'prepare-first';
    final scenario = cold ? 'cold' : 'warm';
    final runId = '$scenario-t$tabs-${lockFirst ? 'lf' : 'pf'}';
    // Cascade targets: pinned now, their users deleted during the run.
    final cascade = peers.sublist(
      64 + cascadeCursor,
      64 + cascadeCursor + _cascadeDeletes,
    );
    cascadeCursor += _cascadeDeletes;
    final setupDb = await openTab(
      _ContentionMeter(_Stats()),
    );
    try {
      await ConstellationAnchorRepository(setupDb, _Profiles()).applyBatch(
        viewerId: viewer,
        ops: batch('$runId-pin', cascade, 0),
        params: _params,
      );
    } finally {
      await setupDb.close();
    }
    // Cold preparation: an emptied MeritRank peer-frame cache.
    // Cold preparation: an emptied MeritRank peer-frame cache. The warm
    // scenario follows the pinning batch, which warmed it.
    if (cold) await fixture.reloadMeritRankGraph(session.writer);

    final stats = _Stats();
    final dbs = [
      for (var t = 0; t < tabs; t++) await openTab(_ContentionMeter(stats)),
    ];
    final revisionBefore = await _cursorRevision(session.writer, viewer);
    final opLogBefore = await _opLogRows(session.writer, viewer);
    var cascaded = 0;
    final wall = Stopwatch()..start();
    try {
      Future<void> tab(int t) async {
        final repository = ConstellationAnchorRepository.withLockOrder(
          dbs[t],
          _Profiles(),
          lockFirstOrder: lockFirst,
        );
        for (var c = 0; c < _callsPerTab; c++) {
          final size = c.isEven ? 1 : 16;
          final start = (t * 7 + c * 3) % (64 - size);
          final ops = batch(
            '$runId-$t-$c',
            peers.sublist(start, start + size),
            t + c,
          );
          final clock = Stopwatch()..start();
          try {
            final result = await repository.applyBatch(
              viewerId: viewer,
              ops: ops,
              params: _params,
            );
            stats.completedCalls++;
            stats.acceptedOps += result.results
                .where((r) => r.status == AnchorOpStatus.ok)
                .length;
          } on Object catch (error) {
            if (!isPostgresDeadlockOrSerializationFailure(error) &&
                error is! PostgresRetryDeadlineExceededException) {
              rethrow;
            }
            stats.exhaustedCalls++;
            stats.exhaustionErrors.add(error.runtimeType.toString());
          }
          stats.callLatenciesMs.add(clock.elapsedMicroseconds / 1000);
        }
      }

      Future<void> cascades() async {
        for (final user in cascade) {
          await Future<void>.delayed(_cascadeSpacing);
          // The pinned anchor goes with its user (ON DELETE CASCADE).
          final deleted = await session.writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = @user'),
            parameters: {'user': user},
          );
          cascaded += deleted.affectedRows;
        }
      }

      await Future.wait([for (var t = 0; t < tabs; t++) tab(t), cascades()]);
    } finally {
      for (final db in dbs) {
        await db.close();
      }
    }
    wall.stop();

    // Every committed accepted write and every cascade-deleted anchor
    // advanced the cursor exactly once; op-log rows match committed calls.
    final revisionAfter = await _cursorRevision(session.writer, viewer);
    expect(
      revisionAfter - revisionBefore,
      BigInt.from(stats.acceptedOps + cascaded),
      reason: '$order/$tabs: cursor advanced once per committed write',
    );
    expect(
      await _opLogRows(session.writer, viewer) - opLogBefore,
      stats.acceptedOps,
      reason: '$order/$tabs: one op-log row per committed operation',
    );
    expect(stats.completedCalls + stats.exhaustedCalls, tabs * _callsPerTab);
    expect(stats.committed, stats.completedCalls);

    final calls = tabs * _callsPerTab;
    final dbMs = stats.dbTime.inMicroseconds / 1000;
    final wastedMs = stats.wastedPreparation.inMicroseconds / 1000;
    final report = <String, Object?>{
      'fixture': 'apply_batch_contention_${scenario}_${tabs}tabs_$order',
      'parameters': {
        'tabs': tabs,
        'order': order,
        'repositoryFlag': 'ConstellationAnchorRepository.lockFirst',
        'flagValue': lockFirst,
        'visibleUsers': 1000,
        'trust': 'dense',
        'callsPerTab': _callsPerTab,
        'batchSizes': [1, 16],
        'scenario': scenario,
        'coldPreparation': cold
            ? 'MeritRank graph reloaded (peer frames emptied) before the run'
            : 'none: MeritRank warm from the preceding batch',
        'cascadeDeletes': _cascadeDeletes,
        'maxAttempts': ConstellationAnchorRepository.applyBatchMaxAttempts,
      },
      'contention': {
        'calls': calls,
        'attemptedTransactions': stats.attempted,
        'committedTransactions': stats.committed,
        'rolledBackTransactions': stats.rolledBack,
        'completedCalls': stats.completedCalls,
        'exhaustedRetries': stats.exhaustedCalls,
        'exhaustionErrors': stats.exhaustionErrors.toList()..sort(),
        'exhaustionPercent': _round(stats.exhaustedCalls / calls * 100),
        'dbTimeMs': _round(dbMs),
        'preparationMs': _round(stats.preparationTime.inMicroseconds / 1000),
        'wastedPreparationMs': _round(wastedMs),
        'wastedPreparationPercent': _round(
          dbMs == 0 ? 0 : wastedMs / dbMs * 100,
        ),
        'cascadedAnchors': cascaded,
        'acceptedOps': stats.acceptedOps,
        'wallMs': wall.elapsedMilliseconds,
        'callLatencyMs': {
          'p50': _round(_percentile(stats.callLatenciesMs, 50)),
          'p95': _round(_percentile(stats.callLatenciesMs, 95)),
          'max': _round(_percentile(stats.callLatenciesMs, 100)),
        },
      },
    };
    final file = File(
      'build/perf/apply_batch_contention_${scenario}_t${tabs}_'
      '${lockFirst ? 'lock_first' : 'prepare_first'}.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(
      'CONTENTION ${jsonEncode(report['contention'])} '
      '${jsonEncode(report['parameters'])}',
    );
    return report;
  }

  group('applyBatch contention gate', () {
    for (final cold in [true, false]) {
      for (final lockFirst in [false, true]) {
        for (final tabs in [2, 4, 8]) {
          test(
            '$tabs tabs of one viewer, ${cold ? 'cold' : 'warm'}, '
            '${lockFirst ? 'lock-first' : 'prepare-first'}: sustained writes '
            'and cascades stay consistent and are recorded',
            () async {
              reports['${cold ? 'cold' : 'warm'}/$tabs/$lockFirst'] = await run(
                tabs: tabs,
                lockFirst: lockFirst,
                cold: cold,
              );
            },
            timeout: const Timeout(Duration(minutes: 10)),
          );
        }
      }
    }

    test('the release lock order is the one the four-tab gate selects', () {
      // Decide from unrounded totals: exhausted calls over all calls (stricter
      // than over all attempted transactions) and wasted preparation over DB
      // time, in either scenario of the four-tab prepare-first run.
      var requiresLockFirst = false;
      for (final scenario in ['cold', 'warm']) {
        final initial = reports['$scenario/4/false'];
        expect(initial, isNotNull, reason: '$scenario prepare-first run');
        final c = initial!['contention']! as Map<String, Object?>;
        final calls = c['calls']! as num;
        final dbMs = c['dbTimeMs']! as num;
        requiresLockFirst =
            requiresLockFirst ||
            (c['exhaustedRetries']! as num) / calls * 100 >
                _exhaustionLimitPercent ||
            (c['wastedPreparationMs']! as num) / dbMs * 100 >
                _wastedPreparationLimitPercent;
      }
      expect(ConstellationAnchorRepository.lockFirst, requiresLockFirst);
    });
  });
}
