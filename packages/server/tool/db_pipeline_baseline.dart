// Mixed-load baseline of the DB pipeline spans (tentura-ev3z.8, review doc §7
// step 1): queue time (admission wait + pool acquire) against SQL time, per
// request, from the Sentry spans the server emits.
//
// Drives the production constellation read (`ConstellationFieldCase` ->
// `ConstellationFieldRepository` through `ConstellationDbScheduler`), anchor
// drags (`ConstellationAnchorRepository.applyBatch`) and the auth/session
// lookup (`SessionRepository` on a second `TenturaDb`, as the `@Named('auth')`
// one) through the real `sentryRequestTracing` middleware, in one isolate on
// one database. Not exercised: HTTP framing, GraphQL parsing, Hasura.
//
// Run through scripts/perf/db_pipeline_baseline.sh. Needs MeritRank loaded for
// the database (`SELECT mr_reset(); SELECT meritrank_init();`).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/app/sentry/sentry_request_context.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/session_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

const _fullOperation = 'ConstellationField';
const _applyOperation = 'ConstellationAnchorsApply';
const _authOperation = 'AuthRefresh';
const _dsn = 'https://public@o123.ingest.sentry.io/1';

/// One configuration of the DB pipeline under test.
typedef _Config = ({String name, int poolSize});

const _configs = <_Config>[
  (name: 'scoped-pool-1', poolSize: 1),
  (name: 'scoped-pool-4', poolSize: 4),
];

double _ms(Duration d) => d.inMicroseconds / 1000;

double _percentile(List<double> sorted, double q) {
  if (sorted.isEmpty) return double.nan;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor();
  final hi = min(lo + 1, sorted.length - 1);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/// What one finished request trace says about where its time went.
final class _RequestTrace {
  _RequestTrace(SentryTransaction tx)
    : operation = tx.tags?['graphql.operation'] ?? '',
      totalMs = _ms(tx.timestamp!.difference(tx.startTimestamp)) {
    for (final span in tx.spans) {
      final ms = _ms(span.endTimestamp!.difference(span.startTimestamp));
      switch (span.context.operation) {
        case 'db.admission.wait':
          admissionMs += ms;
          workClass = span.tags['work.class'];
          if (span.status != const SpanStatus.ok()) refused = true;
        case 'db.pool.acquire':
          acquireMs += ms;
        case 'db.sql':
          sqlMs += ms;
          sqlCount++;
          if (span.context.description?.contains(
                'person_visible_peer',
              ) ??
              false) {
            meritRankSqlMs += ms;
          }
        case 'db.transaction':
          transactionMs += ms;
          transactions++;
        case 'db.retry.backoff':
          backoffMs += ms;
        case 'db.cancel.drain':
          drainMs += ms;
      }
    }
  }

  final String operation;
  final double totalMs;
  String? workClass;
  bool refused = false;
  double admissionMs = 0;
  double acquireMs = 0;
  double sqlMs = 0;
  double meritRankSqlMs = 0;
  double transactionMs = 0;
  double backoffMs = 0;
  double drainMs = 0;
  int sqlCount = 0;
  int transactions = 0;

  double get queueMs => admissionMs + acquireMs;

  /// Request time in neither admission nor a transaction: Drift's executor
  /// lock wait (not a span yet) plus the handler's non-DB work.
  double get outsideMs => totalMs - admissionMs - transactionMs;

  Map<String, Object?> toJson() => {
    'operation': operation,
    'workClass': workClass,
    'refused': refused,
    'totalMs': totalMs,
    'admissionMs': admissionMs,
    'acquireMs': acquireMs,
    'queueMs': queueMs,
    'outsideMs': outsideMs,
    'sqlMs': sqlMs,
    'meritRankSqlMs': meritRankSqlMs,
    'sqlCount': sqlCount,
    'transactionMs': transactionMs,
    'transactions': transactions,
    'backoffMs': backoffMs,
    'drainMs': drainMs,
  };
}

Map<String, Object?> _summary(List<_RequestTrace> rows) {
  Map<String, double> stat(double Function(_RequestTrace) value) {
    final xs = [for (final r in rows) value(r)]..sort();
    return {'p50': _percentile(xs, .5), 'p95': _percentile(xs, .95)};
  }

  return {
    'requests': rows.length,
    'refused': rows.where((r) => r.refused).length,
    'totalMs': stat((r) => r.totalMs),
    'admissionMs': stat((r) => r.admissionMs),
    'acquireMs': stat((r) => r.acquireMs),
    'queueMs': stat((r) => r.queueMs),
    'outsideMs': stat((r) => r.outsideMs),
    'sqlMs': stat((r) => r.sqlMs),
    'meritRankSqlMs': stat((r) => r.meritRankSqlMs),
    'transactionMs': stat((r) => r.transactionMs),
    'sqlCount': stat((r) => r.sqlCount.toDouble()),
  };
}

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

Future<Map<String, Object?>> _runConfig(
  _Config config, {
  required Duration duration,
  required Duration burstEvery,
  required int burstSize,
  required int dragSessions,
  required List<String> viewers,
  required Map<String, List<String>> peersOf,
  required String authAccount,
}) async {
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    isDebugModeOn: false,
    maxConnectionCount: config.poolSize,
  );
  final db = TenturaDb(env);
  final authDb = TenturaDb(env);
  final scheduler = ConstellationDbScheduler.fromEnv(env);
  final profiles = DriftUserProfileBatchLookup(
    db,
    UserAvailabilityRepository(db),
  );
  final fieldCase = ConstellationFieldCase(
    ConstellationFieldRepository.injected(db, profiles, scheduler),
    env: env,
    logger: Logger('baseline'),
  );
  final anchors = ConstellationAnchorRepository.injected(db, scheduler);
  final sessions = SessionRepository(authDb);
  final session = await sessions.create(
    accountId: authAccount,
    expiresIn: const Duration(hours: 1),
  );
  final tokenHash = sha256.convert(utf8.encode(session.token)).toString();

  final traces = <_RequestTrace>[];
  await Sentry.close();
  await Sentry.init((options) {
    options
      ..dsn = _dsn
      ..tracesSampleRate = 1.0
      ..beforeSendTransaction = (transaction, hint) {
        if (transaction.tags?['graphql.operation'] != null) {
          traces.add(_RequestTrace(transaction));
        }
        // Measurement only: nothing leaves the process.
        return null;
      };
  });

  final rng = Random(8);
  final handler = sentryRequestTracing(env: Env(sentryDsn: _dsn))((
    request,
  ) async {
    final operation = request.url.queryParameters['op']!;
    final viewer = request.url.queryParameters['viewer'];
    SentryRequestContext.from(request)!.renameGraphqlOperation(operation);
    switch (operation) {
      case _fullOperation:
        await fieldCase.readSnapshot(
          viewerId: viewer!,
          context: kConstellationContext,
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.full,
          ),
        );
      case _applyOperation:
        final peer = request.url.queryParameters['peer']!;
        await anchors.applyBatch(
          viewerId: viewer!,
          ops: [
            AnchorApplyOp(
              clientOpId: 'baseline-${rng.nextInt(1 << 30)}',
              kind: AnchorOpKind.upsert,
              target: ConstellationAnchorTarget.person(peer),
              position: ConstellationAnchorPosition(
                xUnits: rng.nextDouble() * 1000,
                yUnits: rng.nextDouble() * 1000,
                coordinateSpaceVersion: 1,
              ),
            ),
          ],
        );
      case _authOperation:
        await sessions.findActiveByTokenHash(tokenHash);
    }
    return Response.ok('ok');
  });

  final inflight = <Future<void>>[];
  void fire(String operation, {String? viewer, String? peer}) {
    final uri = Uri(
      scheme: 'http',
      host: 'localhost',
      path: '/api/v2/graphql',
      queryParameters: {
        'op': operation,
        'viewer': ?viewer,
        'peer': ?peer,
      },
    );
    inflight.add(
      Future.sync(() => handler(Request('POST', uri))).then<void>(
        (_) {},
        onError: (Object e) => stderr.writeln('$operation failed: $e'),
      ),
    );
  }

  // Warm-up (discarded): prepared statements, MeritRank peer-frame cache for
  // the first viewer, Sentry, JIT.
  fire(_fullOperation, viewer: viewers.first);
  fire(_authOperation);
  await Future.wait(inflight);
  inflight.clear();
  traces.clear();

  final deadline = DateTime.now().add(duration);
  bool running() => DateTime.now().isBefore(deadline);

  // Screen-open bursts: `burstSize` viewers open the field at once.
  final bursts = Future(() async {
    var n = 0;
    while (running()) {
      for (var i = 0; i < burstSize; i++) {
        fire(
          _fullOperation,
          viewer: viewers[(n * burstSize + i) % viewers.length],
        );
      }
      n++;
      await _sleep(burstEvery);
    }
  });

  // Anchor drags: a drag is 15 `applyBatch` calls 100 ms apart, then a pause.
  final drags = [
    for (var s = 0; s < dragSessions; s++)
      Future(() async {
        final viewer = viewers[(s * 7 + 3) % viewers.length];
        final peers = peersOf[viewer]!;
        await _sleep(Duration(milliseconds: 400 * s));
        while (running()) {
          final peer = peers[rng.nextInt(peers.length)];
          for (var i = 0; i < 15 && running(); i++) {
            fire(_applyOperation, viewer: viewer, peer: peer);
            await _sleep(const Duration(milliseconds: 100));
          }
          await _sleep(Duration(milliseconds: 1500 + rng.nextInt(1500)));
        }
      }),
  ];

  // Auth refresh: a session lookup twice a second.
  final auth = Future(() async {
    while (running()) {
      fire(_authOperation);
      await _sleep(const Duration(milliseconds: 500));
    }
  });

  await Future.wait([bursts, auth, ...drags]);
  await Future.wait(inflight);
  await Sentry.close();
  await sessions.revokeByTokenHash(tokenHash);
  await db.close();
  await authDb.close();

  final byOperation = <String, List<_RequestTrace>>{};
  for (final t in traces) {
    byOperation.putIfAbsent(t.operation, () => []).add(t);
  }
  return {
    'config': config.name,
    'poolSize': config.poolSize,
    'schedulerMaxConcurrent': env.constellationDbMaxConcurrent,
    'perOperation': {
      for (final e in byOperation.entries) e.key: _summary(e.value),
    },
    'requests': [for (final t in traces) t.toJson()],
  };
}

String _f(Object? v) => v is double ? v.toStringAsFixed(1) : '$v';

String _markdown(Map<String, Object?> run) {
  final out = StringBuffer()
    ..writeln('### ${run['config']}')
    ..writeln()
    ..writeln(
      '| Operation | n | refused | total p50 / p95 | queue p50 / p95 '
      '(admission + acquire) | admission p50 / p95 | acquire p50 / p95 '
      '| outside tx+admission p50 / p95 | SQL p50 / p95 | of which visible-set SQL (MeritRank) p50 / p95 '
      '| tx lifetime p50 / p95 | SQL stmts p50 / p95 |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  final ops = run['perOperation']! as Map<String, Object?>;
  for (final e in ops.entries) {
    final s = e.value! as Map<String, Object?>;
    String pair(String key) {
      final m = s[key]! as Map<String, double>;
      return '${_f(m['p50'])} / ${_f(m['p95'])}';
    }

    out.writeln(
      '| ${e.key} | ${s['requests']} | ${s['refused']} | ${pair('totalMs')} '
      '| ${pair('queueMs')} | ${pair('admissionMs')} | ${pair('acquireMs')} '
      '| ${pair('outsideMs')} | ${pair('sqlMs')} | ${pair('meritRankSqlMs')} '
      '| ${pair('transactionMs')} | ${pair('sqlCount')} |',
    );
  }
  return out.toString();
}

Future<void> main(List<String> args) async {
  final out = args.isEmpty
      ? 'build/perf/db_pipeline_baseline.json'
      : args.first;
  final seconds =
      int.tryParse(Platform.environment['BASELINE_SECONDS'] ?? '') ?? 90;
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((r) => stderr.writeln('${r.level} ${r.message}'));

  final env = Env(environment: Environment.test, printEnv: false);
  final database = env.pgDatabase;
  if (!database.startsWith('tentura_ev3z8_baseline')) {
    throw ArgumentError(
      'Refusing to write sessions/anchors into "$database": point '
      'POSTGRES_DBNAME at a throwaway copy named tentura_ev3z8_baseline*.',
    );
  }
  final admin = await Connection.open(
    Endpoint(
      host: env.pgHost,
      port: env.pgPort,
      database: database,
      username: env.pgUsername,
      password: env.pgPassword,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  // Viewers with a dense trust neighbourhood, and the peers they can anchor.
  final rows = await admin.execute('''
SELECT subject, array_agg(object ORDER BY object) AS peers
FROM public.user_trust_edge
GROUP BY subject
HAVING count(*) >= 30
ORDER BY count(*) DESC, subject
LIMIT 40
''');
  final viewers = [for (final r in rows) r[0]! as String];
  final peersOf = {
    for (final r in rows) r[0]! as String: (r[1]! as List).cast<String>(),
  };
  await admin.close();
  if (viewers.length < 10) throw StateError('Too few dense viewers');

  final runs = <Map<String, Object?>>[];
  for (final config in _configs) {
    stderr.writeln('== ${config.name}: ${seconds}s mixed load');
    runs.add(
      await _runConfig(
        config,
        duration: Duration(seconds: seconds),
        burstEvery: const Duration(seconds: 15),
        burstSize: 8,
        dragSessions: 2,
        viewers: viewers,
        peersOf: peersOf,
        authAccount: viewers.first,
      ),
    );
  }
  final report = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'database': database,
    'seconds': seconds,
    'viewers': viewers.length,
    'runs': runs,
  };
  File(out)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
  for (final run in runs) {
    stdout.writeln(_markdown(run));
  }
  stderr.writeln('Wrote $out');
}
