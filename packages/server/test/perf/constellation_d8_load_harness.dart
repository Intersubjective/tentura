// D8 load harness (#235 U26): 1,000 simulated client sessions against W
// worker isolates that each run the production constellation read and write
// path on one database connection, as a server web worker does:
//
// * `TenturaDb(env)` (one pinned connection), `ConstellationDbScheduler`
//   (production config from `Env`), `ConstellationFieldRepository.injected`,
//   the isolate-scoped single-flight of `ConstellationFieldCase`,
//   `ConstellationAnchorRepository.injected` (lock-first `applyBatch`),
//   `DriftUserProfileBatchLookup`, and the GraphQL mapping + JSON encoding;
// * a per-worker `PgNotificationService` LISTEN connection and the
//   dirty-generation broadcast of `WebsocketPathEntityChanges` (one hint per
//   `env.constellationFieldBroadcastWindow`, re-armed when markers arrived).
//
// Not exercised: HTTP/WebSocket framing, GraphQL parsing and auth. A measuring
// decorator around the scheduler and a measuring `TenturaDb` subclass record
// admission, scheduler dispatch, Drift lane acquisition, the MeritRank
// visible-set statement, the statement span and execution end; they add clock
// reads only and change no decision.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import 'constellation_d8_load_model.dart';

double _nowMs() => DateTime.now().microsecondsSinceEpoch / 1000;

/// Connection facts a worker isolate rebuilds its `Env` from.
typedef D8PgTarget = ({
  String host,
  int port,
  String database,
  String username,
  String password,
});

/// A smoke run (`TENTURA_D8_SMOKE_SCALE` < 1) compresses the server's field
/// broadcast window with the timeline; otherwise the 30 s default would outlast
/// the whole compressed window and no FULL could ever be requested.
Duration? _smokeBroadcastWindow() {
  final scale = double.tryParse(
    Platform.environment['TENTURA_D8_SMOKE_SCALE'] ?? '',
  );
  return scale == null || scale >= 1
      ? null
      : Duration(milliseconds: (30000 * scale).round());
}

Env _envFor(D8PgTarget pg) => Env(
  constellationFieldBroadcastWindow: _smokeBroadcastWindow(),
  environment: Environment.test,
  pgHost: pg.host,
  pgPort: pg.port,
  pgDatabase: pg.database,
  pgUsername: pg.username,
  pgPassword: pg.password,
  printEnv: false,
  isDebugModeOn: false,
);

// ---------------------------------------------------------------------------
// Dataset

/// What [seedD8Dataset] created.
final class D8Dataset {
  const D8Dataset({
    required this.users,
    required this.trustEdges,
    required this.requests,
    required this.meritRankEdges,
    required this.publicationEdges,
  });

  final int users;
  final int trustEdges;
  final int requests;
  final int meritRankEdges;

  /// Existing trust edges the publications rewrite.
  final List<(String, String)> publicationEdges;

  Map<String, Object?> toJson() => {
    'users': users,
    'clusters': 3,
    'trustEdges': trustEdges,
    'requests': requests,
    'meritRankEdges': meritRankEdges,
    'model':
        'scripts/perf/constellation_synth.sql shape: 3 clusters of 1000 '
        'users, ~15 random reciprocal in-cluster pairs per user, 10 '
        'discoverable Requests per cluster-0 user and 2 per other user',
  };
}

String d8UserId(int n) => 'Ud8${n.toString().padLeft(9, '0')}';

/// The `tentura_perfsynth` shape (V ≈ 1,000 visible peers per viewer) on a
/// fresh schema: 3,000 users, reciprocal in-cluster trust mirrored into
/// MeritRank by `meritrank_init()`, 14,000 discoverable open Requests.
Future<D8Dataset> seedD8Dataset(Connection writer) async {
  await writer.execute('SELECT mr_reset()');
  await writer.execute('SELECT setseed(0.235)');
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT 'Ud8' || lpad(n::text, 9, '0'), 'D8 user ' || n, 'pk-d8-' || n
FROM generate_series(1, 3000) n
''');
  await writer.execute('''
CREATE TEMP TABLE d8_pairs AS
SELECT DISTINCT 'Ud8' || lpad(i::text, 9, '0') AS a,
       'Ud8' || lpad((((i - 1) / 1000) * 1000 + 1
         + floor(random() * 1000))::int::text, 9, '0') AS b
FROM generate_series(1, 3000) i, generate_series(1, 15) k
''');
  await writer.execute('DELETE FROM d8_pairs WHERE a = b');
  await writer.runTx((tx) async {
    // A bulk fixture load, not relationship changes clients must hear of.
    await tx.execute(
      "SELECT set_config('tentura.suppress_relationship_notify', '1', true)",
    );
    await tx.execute('''
INSERT INTO public.user_trust_edge
  (subject, object, trust_w, target_w, prev_sent_weight)
SELECT a, b, 1, 1, 1 FROM d8_pairs
UNION
SELECT b, a, 1, 1, 1 FROM d8_pairs
ON CONFLICT DO NOTHING
''');
  });
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
SELECT 'Bd8' || lpad(((u - 1) * 10 + k)::text, 9, '0'),
       'Ud8' || lpad(u::text, 9, '0'),
       'D8 request ' || u || '-' || k, '', 0, now(), true
FROM generate_series(1, 3000) u, generate_series(1, 10) k
WHERE u <= 1000 OR k <= 2
''');
  final edges = await writer.execute(
    'SELECT a, b FROM d8_pairs ORDER BY a, b',
  );
  final shuffled = [
    for (final row in edges) (row[0]! as String, row[1]! as String),
  ]..shuffle(Random(235));
  await writer.execute('DROP TABLE d8_pairs');
  await writer.execute('ANALYZE');
  await writer.execute('SELECT meritrank_init()');
  Future<int> count(String sql) async =>
      int.parse((await writer.execute(sql)).first.first.toString());
  final meritRankEdges = await count('SELECT count(*) FROM mr_edgelist()');
  if (meritRankEdges == 0) {
    throw StateError('meritrank_init() loaded no edges');
  }
  return D8Dataset(
    users: await count(
      "SELECT count(*) FROM public.\"user\" WHERE id LIKE 'Ud8%'",
    ),
    trustEdges: await count('SELECT count(*) FROM public.user_trust_edge'),
    requests: await count(
      "SELECT count(*) FROM public.beacon WHERE id LIKE 'Bd8%'",
    ),
    meritRankEdges: meritRankEdges,
    publicationEdges: shuffled.take(500).toList(),
  );
}

/// The D8 population: 1,000 sessions. One tab per viewer spreads 1,000
/// viewers over the three clusters; two tabs share 500 viewers.
List<D8SessionSpec> d8SessionSpecs(
  D8Scenario scenario,
  int workers, {
  int sessions = d8Sessions,
}) {
  final tabs = scenario.tabsPerViewer;
  final viewers = sessions ~/ tabs;
  final step = 3000 ~/ viewers;
  return [
    for (var v = 0; v < viewers; v++)
      for (var t = 0; t < tabs; t++)
        D8SessionSpec(
          sessionId: 's${(v * tabs + t).toString().padLeft(4, '0')}',
          viewerId: d8UserId(1 + v * step),
          tabId: 't$t',
          wsWorker: (v * tabs + t) % workers,
        ),
  ];
}

final class D8SessionSpec {
  const D8SessionSpec({
    required this.sessionId,
    required this.viewerId,
    required this.tabId,
    required this.wsWorker,
  });

  final String sessionId;
  final String viewerId;
  final String tabId;

  /// The worker isolate holding this session's WebSocket.
  final int wsWorker;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'viewerId': viewerId,
    'tabId': tabId,
    'wsWorker': wsWorker,
  };
}

// ---------------------------------------------------------------------------
// Worker isolate

final Object _probeKey = Object();

final class _Computation {
  _Computation(this.id, this.admittedMs);

  final String id;
  final double admittedMs;

  /// Scheduler dispatch, BEFORE the body asks Drift for the lane.
  double? startedMs;
  double? executedMs;

  /// First moment the body's transaction owns the Drift lane.
  double? laneAcquiredMs;
  double? meritRankStartedMs;
  double? meritRankCompletedMs;

  /// First to last statement of the transaction (contains the MR statement).
  double? dbStartedMs;
  double? dbCompletedMs;

  void statementStarted() {
    if (laneAcquiredMs != null) dbStartedMs ??= _nowMs();
  }

  void statementCompleted() {
    if (dbStartedMs != null) dbCompletedMs = _nowMs();
  }
}

final class _Probe {
  _Computation? computation;
}

/// Records admission (scheduler entry) and execution start/end around the
/// production scheduler; the scheduling itself is the scheduler's.
final class _TimedAdmission implements ConstellationDbAdmissionPort {
  _TimedAdmission(this._inner, this._worker);

  final ConstellationDbScheduler _inner;
  final int _worker;
  var _seq = 0;

  @override
  Future<T> run<T>(ConstellationDbWorkKind kind, Future<T> Function() body) {
    final computation = _Computation(
      'w$_worker-${kind.name}-${++_seq}',
      _nowMs(),
    );
    final probe = Zone.current[_probeKey];
    if (probe is _Probe) probe.computation = computation;
    // A queued body is started from whichever zone releases the lane, so
    // re-enter the caller's zone for `_TimedDb` to find this computation.
    final callerZone = Zone.current;
    return _inner.run(kind, () async {
      computation.startedMs = _nowMs();
      try {
        return await callerZone.run(body);
      } finally {
        computation.executedMs = _nowMs();
      }
    });
  }
}

/// `TenturaDb` that stamps the current computation (found through the zone
/// the production code runs in) when its transaction gets the lane and around
/// its statements. It issues the same statements as the production class.
final class _TimedDb extends TenturaDb {
  _TimedDb(super.env);

  static _Computation? get _computation {
    final probe = Zone.current[_probeKey];
    return probe is _Probe ? probe.computation : null;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    final computation = _computation;
    return super.transaction(() {
      computation?.laneAcquiredMs ??= _nowMs();
      return action();
    }, requireNew: requireNew);
  }

  @override
  Future<void> customStatement(String statement, [List<dynamic>? args]) async {
    final computation = _computation?..statementStarted();
    try {
      await super.customStatement(statement, args);
    } finally {
      computation?.statementCompleted();
    }
  }

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation<dynamic, dynamic>> readsFrom = const {},
  }) {
    final select = super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
    final computation = _computation;
    return computation == null
        ? select
        : _TimedSelect(
            select,
            computation,
            meritRank: query.contains('person_visible_peers_symmetric'),
          );
  }
}

final class _TimedSelect extends Selectable<QueryRow> {
  _TimedSelect(this._select, this._computation, {required this.meritRank});

  final Selectable<QueryRow> _select;
  final _Computation _computation;
  final bool meritRank;

  @override
  Future<List<QueryRow>> get() async {
    _computation.statementStarted();
    if (meritRank) _computation.meritRankStartedMs ??= _nowMs();
    try {
      return await _select.get();
    } finally {
      if (meritRank) _computation.meritRankCompletedMs = _nowMs();
      _computation.statementCompleted();
    }
  }

  @override
  Stream<List<QueryRow>> watch() => _select.watch();
}

typedef _WorkerArgs = ({SendPort toMain, int worker, D8PgTarget pg});

Future<void> _workerMain(_WorkerArgs args) async {
  final worker = args.worker;
  final toMain = args.toMain;
  final env = _envFor(args.pg);
  final db = _TimedDb(env);
  final profiles = DriftUserProfileBatchLookup(
    db,
    UserAvailabilityRepository(db),
  );
  final scheduler = ConstellationDbScheduler.fromEnv(env);
  final admission = _TimedAdmission(scheduler, worker);
  final fieldCase = ConstellationFieldCase(
    ConstellationFieldRepository.injected(db, profiles, admission),
    env: env,
    logger: Logger('D8Worker$worker'),
  );
  final anchors = ConstellationAnchorRepository.injected(
    db,
    profiles,
    admission,
  );
  final computations = Expando<_Computation>();

  // Fan-out as in WebsocketPathEntityChanges: one broadcast per window.
  final notifications = await PgNotificationService.create(
    env,
    const PostgresNotificationConnector(),
  );
  var dirtyGeneration = 0;
  var markers = 0;
  var broadcasts = 0;
  Timer? broadcastTimer;
  void scheduleBroadcast() {
    if (broadcastTimer != null) return;
    broadcastTimer = Timer(env.constellationFieldBroadcastWindow, () {
      final generation = dirtyGeneration;
      broadcasts++;
      toMain.send({'type': 'hint', 'worker': worker, 'atMs': _nowMs()});
      broadcastTimer = null;
      if (dirtyGeneration > generation) scheduleBroadcast();
    });
  }

  final listening = notifications.entityChangeNotifications.listen((payload) {
    final data = jsonDecode(payload);
    if (data is Map<String, dynamic> &&
        data['entity'] == 'constellation_field' &&
        data['id'] == 'global' &&
        data['event'] == 'update' &&
        data['user_ids'] is List &&
        (data['user_ids'] as List).isEmpty) {
      markers++;
      dirtyGeneration++;
      scheduleBroadcast();
    }
  });

  Map<String, Object?> timings(_Computation? c) => {
    'computationId': c?.id,
    'admittedMs': c?.admittedMs,
    'startedMs': c?.startedMs,
    'executedMs': c?.executedMs,
    'laneAcquiredMs': c?.laneAcquiredMs,
    'meritRankStartedMs': c?.meritRankStartedMs,
    'meritRankCompletedMs': c?.meritRankCompletedMs,
    'dbStartedMs': c?.dbStartedMs,
    'dbCompletedMs': c?.dbCompletedMs,
  };

  Future<void> full(Map<String, Object?> message) async {
    final receivedMs = _nowMs();
    final probe = _Probe();
    final future = runZoned(
      () => fieldCase.readSnapshot(
        viewerId: message['viewer']! as String,
        context: kConstellationContext,
        params: (
          filters: ConstellationFieldMembershipFilters.defaults,
          projection: ConstellationProjection.full,
        ),
      ),
      zoneValues: {_probeKey: probe},
    );
    var computation = probe.computation;
    var follower = false;
    if (computation != null) {
      computations[future] = computation;
    } else {
      computation = computations[future];
      follower = true;
    }
    try {
      final snapshot = await future;
      final body = jsonEncode(constellationFieldToGqlMap(snapshot));
      toMain.send({
        'type': 'fullDone',
        'req': message['req'],
        'worker': worker,
        'ok': true,
        'follower': follower,
        'receivedMs': receivedMs,
        'encodedMs': _nowMs(),
        'bytes': body.length,
        'peers': [for (final p in snapshot.peers.take(3)) p.id],
        ...timings(computation),
      });
    } on Object catch (error) {
      toMain.send({
        'type': 'fullDone',
        'req': message['req'],
        'worker': worker,
        'ok': false,
        'follower': follower,
        'receivedMs': receivedMs,
        'encodedMs': _nowMs(),
        'retryAfterMs': error is ConstellationException
            ? error.retryAfter?.inMilliseconds
            : null,
        'error': '$error',
        ...timings(computation),
      });
    }
  }

  Future<void> write(Map<String, Object?> message) async {
    final receivedMs = _nowMs();
    final probe = _Probe();
    try {
      final result = await runZoned(
        () => anchors.applyBatch(
          viewerId: message['viewer']! as String,
          ops: [
            AnchorApplyOp(
              clientOpId: message['op']! as String,
              kind: AnchorOpKind.upsert,
              target: ConstellationAnchorTarget.person(
                message['peer']! as String,
              ),
              position: ConstellationAnchorPosition(
                xUnits: (message['x']! as num).toDouble(),
                yUnits: (message['y']! as num).toDouble(),
                coordinateSpaceVersion: 1,
              ),
            ),
          ],
          params: const AnchorApplyParams(
            context: kConstellationContext,
            filters: ConstellationFieldMembershipFilters.defaults,
          ),
        ),
        zoneValues: {_probeKey: probe},
      );
      jsonEncode(constellationAnchorProjectionToGqlMap(result.projection));
      toMain.send({
        'type': 'writeDone',
        'req': message['req'],
        'worker': worker,
        'ok': true,
        'status': result.results.first.status.name,
        'receivedMs': receivedMs,
        'encodedMs': _nowMs(),
        ...timings(probe.computation),
      });
    } on Object catch (error) {
      toMain.send({
        'type': 'writeDone',
        'req': message['req'],
        'worker': worker,
        'ok': false,
        'error': '$error',
        'receivedMs': receivedMs,
        'encodedMs': _nowMs(),
        ...timings(probe.computation),
      });
    }
  }

  final inbox = ReceivePort();
  inbox.listen((raw) async {
    final message = raw! as Map<String, Object?>;
    switch (message['type']) {
      case 'full':
        unawaited(full(message));
      case 'write':
        unawaited(write(message));
      case 'stop':
        broadcastTimer?.cancel();
        await listening.cancel();
        await notifications.dispose();
        await db.close();
        toMain.send({
          'type': 'stopped',
          'worker': worker,
          'markers': markers,
          'broadcasts': broadcasts,
          'schedulerCompletedFull': scheduler.stats.completedFull,
          'schedulerMaxQueueAgeMs':
              scheduler.stats.maxQueueAge.inMicroseconds / 1000,
        });
        inbox.close();
    }
  });
  toMain.send({
    'type': 'ready',
    'worker': worker,
    'port': inbox.sendPort,
    'broadcastWindowMs': env.constellationFieldBroadcastWindow.inMilliseconds,
    'scheduler': {
      'maxConcurrent': scheduler.config.maxConcurrent,
      'maxQueued': scheduler.config.maxQueued,
      'queueDeadlineMs': scheduler.config.queueDeadline.inMilliseconds,
      'reservedRefreshShare': scheduler.config.reservedRefreshShare,
      'retryAfterMs': scheduler.config.retryAfter.inMilliseconds,
    },
    'pinnedPool': !env.driftTransactionPinnedPoolEnabled,
  });
}

// ---------------------------------------------------------------------------
// Main isolate: sessions, publications, writes, records

final class _Session {
  _Session(this.spec);

  final D8SessionSpec spec;
  late final D8ClientPolicy policy;
  bool connected = false;
  int completedOk = 0;
  List<String> peers = const [];
}

final class _Recording {
  _Recording(this.t0Ms, this.endMs);

  final double t0Ms;
  final double endMs;
  final refreshes = <Map<String, Object?>>[];
  final failedRefreshes = <Map<String, Object?>>[];
  final publications = <Map<String, Object?>>[];
  final writes = <Map<String, Object?>>[];
  final failedWrites = <Map<String, Object?>>[];

  /// Writes dispatched in the window, until their response arrives.
  final outstandingWrites = <int, Map<String, Object?>>{};

  /// Writes whose response came after the window's end.
  final unfinishedWrites = <Map<String, Object?>>[];
  int writeRequests = 0;
  final reconnects = <Map<String, Object?>>[];
  final hints = <Map<String, Object?>>[];
  int fullRequests = 0;
  int followers = 0;

  bool covers(double atMs) => atMs >= t0Ms && atMs <= endMs;
  double rel(double atMs) => double.parse((atMs - t0Ms).toStringAsFixed(3));
}

final class D8Harness {
  D8Harness._(this._dataset, this._publisher, int workers)
    : _workers = List<SendPort?>.filled(workers, null);

  final List<SendPort?> _workers;
  final _sessions = <_Session>[];
  final D8Dataset _dataset;
  final Connection _publisher;
  final _random = Random(235);
  final _inbox = ReceivePort();
  late final StreamSubscription<Object?> _inboxSub;
  final _pending = <int, void Function(Map<String, Object?>)>{};
  final _ready = <Map<String, Object?>>[];
  final _stopped = <Map<String, Object?>>[];
  var _req = 0;
  var _publicationIndex = 0;
  var _edgeIndex = 0;
  var _writeSeq = 0;
  _Recording? _recording;

  /// Worker-side settings every worker reported (identical across workers).
  late final Map<String, Object?> workerConfig;

  static Future<D8Harness> start({
    required D8PgTarget pg,
    required int workers,
    required List<D8SessionSpec> sessions,
    required D8Dataset dataset,
  }) async {
    final publisher = await Connection.open(
      Endpoint(
        host: pg.host,
        port: pg.port,
        database: pg.database,
        username: pg.username,
        password: pg.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    final harness = D8Harness._(dataset, publisher, workers);
    harness._inboxSub = harness._inbox.listen(harness._onWorkerMessage);
    for (var w = 0; w < workers; w++) {
      await Isolate.spawn<_WorkerArgs>(
        _workerMain,
        (toMain: harness._inbox.sendPort, worker: w, pg: pg),
        debugName: 'D8 worker #$w',
      );
    }
    await harness._until(
      () => harness._ready.length == workers,
      const Duration(minutes: 2),
    );
    final first = harness._ready.first;
    harness.workerConfig = {
      'workers': workers,
      'broadcastWindowMs': first['broadcastWindowMs'],
      'scheduler': first['scheduler'],
      'singleConnectionPerWorker': first['pinnedPool'],
    };
    for (final spec in sessions) {
      final session = _Session(spec);
      session.policy = harness._policyFor(session);
      harness._sessions.add(session);
    }
    return harness;
  }

  SendPort _port(int worker) => _workers[worker]!;

  D8ClientPolicy _policyFor(_Session session) => D8ClientPolicy(
    jitterMs: d8JitterMs(session.spec.viewerId),
    nowMs: _nowMs,
    schedule: (delayMs, callback) {
      final timer = Timer(
        Duration(microseconds: max(0, (delayMs * 1000).round())),
        callback,
      );
      return (cancel: timer.cancel);
    },
    startFull: () => _sendFull(session),
  );

  void _onWorkerMessage(Object? raw) {
    final message = raw! as Map<String, Object?>;
    switch (message['type']) {
      case 'ready':
        _workers[message['worker']! as int] = message['port']! as SendPort;
        _ready.add(message);
      case 'hint':
        unawaited(_deliverHint(message));
      case 'stopped':
        _stopped.add(message);
      default:
        final callback = _pending.remove(message['req']);
        callback?.call(message);
    }
  }

  /// Delivers a worker's broadcast to its connected sessions, yielding every
  /// 100 sends as the production fan-out does.
  Future<void> _deliverHint(Map<String, Object?> message) async {
    final worker = message['worker']! as int;
    final at = message['atMs']! as double;
    final recording = _recording;
    if (recording != null && recording.covers(at)) {
      recording.hints.add({'workerId': worker, 'atMs': recording.rel(at)});
    }
    var sent = 0;
    for (final session in _sessions) {
      if (session.spec.wsWorker != worker || !session.connected) continue;
      session.policy.onHint();
      if (++sent % 100 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  void _sendFull(_Session session) {
    final req = ++_req;
    final worker = _random.nextInt(_workers.length);
    final requestedAt = _nowMs();
    final recording = _recording;
    if (recording != null && recording.covers(requestedAt)) {
      recording.fullRequests++;
    }
    _pending[req] = (reply) {
      final completedAt = _nowMs();
      final ok = reply['ok']! as bool;
      if (ok) {
        session
          ..completedOk += 1
          ..peers = (reply['peers']! as List<Object?>).cast<String>();
      }
      final current = _recording;
      if (current != null &&
          current.covers(requestedAt) &&
          completedAt <= current.endMs) {
        final record = {
          'sessionId': session.spec.sessionId,
          'workerId': worker,
          'computationId': reply['computationId'],
          'requestedAtMs': requestedAt,
          'receivedAtMs': reply['receivedMs'],
          'admittedAtMs': reply['admittedMs'],
          'startedAtMs': reply['startedMs'],
          'executedAtMs': reply['executedMs'],
          'encodedAtMs': reply['encodedMs'],
          'completedAtMs': completedAt,
          'follower': reply['follower'],
          if (ok) 'bytes': reply['bytes'],
          if (!ok) 'retryAfterMs': reply['retryAfterMs'],
          if (!ok) 'error': reply['error'],
        };
        (ok ? current.refreshes : current.failedRefreshes).add(record);
        // One write per 100 completed reads; a RETRY_LATER is not a read.
        if (ok && current.refreshes.length % d8ReadsPerWrite == 0) {
          _sendWrite(session);
        }
        if (ok && reply['follower'] == true) current.followers++;
      }
      final retryAfter = reply['retryAfterMs'];
      session.policy.onFullCompleted(
        ok: ok,
        retryAfterMs: ok
            ? null
            : retryAfter is num
            ? retryAfter.toDouble()
            // A failure without a backoff hint: the client retries on its
            // next hint; model a 2 s not-before so the session is not lost.
            : 2000,
      );
    };
    _port(worker).send({
      'type': 'full',
      'req': req,
      'viewer': session.spec.viewerId,
    });
  }

  /// One interactive 1-op `applyBatch` (anchor upsert of a peer the viewer
  /// was last shown), on a random worker.
  void _sendWrite(_Session trigger) {
    final candidates = trigger.peers.isNotEmpty
        ? trigger
        : _sessions.firstWhere(
            (s) => s.peers.isNotEmpty,
            orElse: () => trigger,
          );
    if (candidates.peers.isEmpty) return;
    final req = ++_req;
    final worker = _random.nextInt(_workers.length);
    final seq = ++_writeSeq;
    final admittedAt = _nowMs();
    final open = _recording;
    final recording = open != null && open.covers(admittedAt) ? open : null;
    final dispatched = {
      'sessionId': candidates.spec.sessionId,
      'viewerId': candidates.spec.viewerId,
      'workerId': worker,
      'admittedAtMs': admittedAt,
    };
    if (recording != null) {
      recording.writeRequests++;
      recording.outstandingWrites[req] = dispatched;
    }
    _pending[req] = (reply) {
      final completedAt = _nowMs();
      if (recording == null) return;
      recording.outstandingWrites.remove(req);
      final record = {
        ...dispatched,
        'computationId': reply['computationId'],
        'receivedAtMs': reply['receivedMs'],
        'schedulerAdmittedAtMs': reply['admittedMs'],
        'startedAtMs': reply['startedMs'],
        'laneAcquiredAtMs': reply['laneAcquiredMs'],
        'meritRankStartedAtMs': reply['meritRankStartedMs'],
        'meritRankCompletedAtMs': reply['meritRankCompletedMs'],
        'dbStartedAtMs': reply['dbStartedMs'],
        'dbCompletedAtMs': reply['dbCompletedMs'],
        'executionCompletedAtMs': reply['executedMs'],
        'encodedAtMs': reply['encodedMs'],
        'completedAtMs': completedAt,
        'status': reply['status'],
        if (reply['ok'] != true) 'error': reply['error'],
      };
      if (completedAt > recording.endMs) {
        // Answered after the window: not a sample of it, but not lost either.
        recording.unfinishedWrites.add(record);
        return;
      }
      (reply['ok'] == true && reply['startedMs'] != null
              ? recording.writes
              : recording.failedWrites)
          .add(record);
    };
    _port(worker).send({
      'type': 'write',
      'req': req,
      'viewer': candidates.spec.viewerId,
      'peer': candidates.peers[seq % candidates.peers.length],
      'op': 'd8-$seq',
      'x': (seq % 9) - 4.0,
      'y': ((seq * 3) % 9) - 4.0,
    });
  }

  /// One trust change plus its MeritRank publication: the statement trigger
  /// on `user_trust_edge` emits the global `constellation_field` marker at
  /// commit, as a real trust change does.
  Future<void> _publish() async {
    final (subject, object) = _dataset
        .publicationEdges[_edgeIndex++ % _dataset.publicationEdges.length];
    final weight = _edgeIndex.isEven ? 1.0 : 0.9;
    await _publisher.runTx((tx) async {
      await tx.execute(
        Sql.named(
          'UPDATE public.user_trust_edge '
          'SET trust_w = @w, target_w = @w, prev_sent_weight = @w '
          'WHERE subject = @a AND object = @b',
        ),
        parameters: {'w': weight, 'a': subject, 'b': object},
      );
      await tx.execute(
        Sql.named(
          "SELECT mr_put_edge(@a, @b, @w::double precision, ''::text, 0)",
        ),
        parameters: {'w': weight, 'a': subject, 'b': object},
      );
    });
    final publishedAt = _nowMs();
    final recording = _recording;
    if (recording != null) {
      recording.publications.add({
        'generation': ++_publicationIndex,
        'publishedAtMs': publishedAt,
        'edge': [subject, object],
        'weight': weight,
      });
    }
  }

  Future<void> _until(bool Function() done, Duration timeout) async {
    final deadline = _nowMs() + timeout.inMilliseconds;
    while (!done()) {
      if (_nowMs() > deadline) {
        throw TimeoutException('D8 harness wait exceeded $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  bool get _idle =>
      _sessions.every((s) => !s.policy.inFlight) && _pending.isEmpty;

  /// Opens every session (staggered over 60 s, each with its initial load),
  /// waits for every initial FULL, then until each session's lazy spacing has
  /// passed, so the first publication reaches every session at once.
  Future<Map<String, Object?>> warmUp({double scale = 1}) async {
    final started = _nowMs();
    final spreadMs = (60000 * scale).round();
    for (var i = 0; i < _sessions.length; i++) {
      final session = _sessions[i]..connected = true;
      Timer(
        Duration(milliseconds: spreadMs * i ~/ _sessions.length),
        session.policy.onLoadOrCatchUp,
      );
    }
    await _until(
      () => _sessions.every((s) => s.completedOk > 0) && _idle,
      const Duration(minutes: 20),
    );
    final loaded = _nowMs();
    await _settle();
    return {
      'loadedAllMs': loaded - started,
      'warmUpMs': _nowMs() - started,
    };
  }

  Future<void> _settle() async {
    // A FULL still pending from a late hint moves `lastDispatch` while waiting,
    // so recompute until nothing is in flight and the last spacing has passed.
    while (true) {
      await _until(() => _idle, const Duration(minutes: 10));
      final lastDispatch = _sessions
          .map((s) => s.policy.lastFullAtMs ?? 0)
          .reduce(max);
      final ready =
          lastDispatch + D8ClientPolicy.lazySpacingMs + 3001 + 500 - _nowMs();
      if (ready <= 0) return;
      await Future<void>.delayed(Duration(milliseconds: ready.ceil()));
    }
  }

  /// Runs one level of [scenario] and returns its evidence.
  Future<Map<String, Object?>> run(
    D8Scenario scenario,
    D8Level level,
    Map<String, Object?> deployment, {
    double scale = 1,
  }) async {
    final plan = d8PlanFor(scenario, level, scale: scale);
    _publicationIndex = 0;
    final t0 = _nowMs();
    final recording = _Recording(t0, t0 + plan.durationMs);
    _recording = recording;
    final timers = <Timer>[];
    final publications = <Future<void>>[];
    var publishing = Future<void>.value();
    for (final at in plan.publicationsAtMs) {
      timers.add(
        Timer(Duration(milliseconds: at), () {
          // Serialised: a slow publication delays the next, never reorders.
          publishing = publishing.then((_) => _publish());
          publications.add(publishing);
        }),
      );
    }
    // The read-driven cadence (one write per d8ReadsPerWrite FULLs) can leave a
    // scenario short of a meaningful p95: top it up to d8WriteMinimumSamples + 2
    // dispatches, spread over the first 90 % of the window so they can finish.
    // Smoke runs (scale < 1) skip it: their short windows cannot absorb the
    // extra writes without starving the FULLs they exist to exercise.
    final floorWrites = scale < 1 ? 0 : d8WriteMinimumSamples + 2;
    for (var i = 1; i <= floorWrites; i++) {
      timers.add(
        Timer(
          Duration(
            microseconds: (plan.durationMs * 900 * i / floorWrites).round(),
          ),
          () {
            if (recording.writeRequests < i) _sendWrite(_sessions.first);
          },
        ),
      );
    }
    final disconnectAt = plan.disconnectAtMs;
    final reconnectAt = plan.reconnectAtMs;
    final disconnectedAt = <String, double>{};
    if (disconnectAt != null && reconnectAt != null) {
      timers
        ..add(
          Timer(Duration(milliseconds: disconnectAt), () {
            for (final s in _sessions) {
              s.connected = false;
              disconnectedAt[s.spec.sessionId] = _nowMs();
            }
          }),
        )
        ..add(
          Timer(Duration(milliseconds: reconnectAt), () async {
            var n = 0;
            for (final s in _sessions) {
              s.connected = true;
              recording.reconnects.add({
                'sessionId': s.spec.sessionId,
                'disconnectedAtMs': disconnectedAt[s.spec.sessionId],
                'reconnectedAtMs': _nowMs(),
              });
              s.policy.onLoadOrCatchUp();
              if (++n % 100 == 0) await Future<void>.delayed(Duration.zero);
            }
          }),
        );
    }
    await Future<void>.delayed(Duration(milliseconds: plan.durationMs));
    for (final t in timers) {
      t.cancel();
    }
    await Future.wait(publications);
    _recording = null;
    await _settle();
    // Dispatched in the window and not answered by its end (still outstanding,
    // or answered late): reported, never silently dropped.
    final window = <String, Object?>{
      'unfinishedWrites': [
        ...recording.unfinishedWrites,
        ...recording.outstandingWrites.values,
      ],
      'writeRequests': recording.writeRequests,
    };
    return _evidence(
      scenario,
      level,
      plan,
      recording,
      deployment,
      scale,
      window,
    );
  }

  Map<String, Object?> _evidence(
    D8Scenario scenario,
    D8Level level,
    D8Plan plan,
    _Recording r,
    Map<String, Object?> deployment,
    double scale,
    Map<String, Object?> window,
  ) {
    final publications = [
      for (final p in r.publications)
        {...p, 'publishedAtMs': r.rel(p['publishedAtMs']! as double)},
    ];
    int? generationAt(double atMs) {
      int? newest;
      for (final p in publications) {
        if ((p['publishedAtMs']! as double) <= atMs) {
          newest = p['generation']! as int;
        }
      }
      return newest;
    }

    double? publishedAt(int generation) =>
        publications.firstWhere(
              (p) => p['generation'] == generation,
            )['publishedAtMs']
            as double?;

    final completed = <Map<String, Object?>>[];
    var capturedBeforeFirstPublication = 0;
    var withoutComputation = 0;
    for (final raw in r.refreshes) {
      if (raw['startedAtMs'] == null || raw['admittedAtMs'] == null) {
        withoutComputation++;
        continue;
      }
      final started = r.rel(raw['startedAtMs']! as double);
      final generation = generationAt(started);
      if (generation == null) {
        capturedBeforeFirstPublication++;
        continue;
      }
      completed.add({
        ...raw,
        for (final key in [
          'requestedAtMs',
          'receivedAtMs',
          'admittedAtMs',
          'startedAtMs',
          'executedAtMs',
          'encodedAtMs',
          'completedAtMs',
        ])
          key: r.rel(raw[key]! as double),
        'generation': generation,
        'generationCapturedAtMs': started,
        'invalidatedAtMs': publishedAt(generation),
      });
    }
    final requests = [
      for (final c in completed)
        {
          'sessionId': c['sessionId'],
          'workerId': c['workerId'],
          'computationId': c['computationId'],
          'generation': c['generation'],
          'startedAtMs': c['requestedAtMs'],
          'completedAtMs': c['completedAtMs'],
        },
    ];
    final reconnects = [
      for (final rc in r.reconnects)
        () {
          final disconnected = r.rel(rc['disconnectedAtMs']! as double);
          final reconnected = r.rel(rc['reconnectedAtMs']! as double);
          var acknowledged = 0;
          for (final c in completed) {
            if (c['sessionId'] == rc['sessionId'] &&
                (c['completedAtMs']! as double) <= disconnected &&
                (c['generation']! as int) > acknowledged) {
              acknowledged = c['generation']! as int;
            }
          }
          return {
            'sessionId': rc['sessionId'],
            'disconnectedAtMs': disconnected,
            'reconnectedAtMs': reconnected,
            'generation': generationAt(reconnected) ?? 0,
            'lastAcknowledgedGeneration': acknowledged,
          };
        }(),
    ];
    Map<String, Object?> relWrite(Map<String, Object?> w) => {
      ...w,
      for (final key in [
        'admittedAtMs',
        'receivedAtMs',
        'schedulerAdmittedAtMs',
        'startedAtMs',
        'laneAcquiredAtMs',
        'meritRankStartedAtMs',
        'meritRankCompletedAtMs',
        'dbStartedAtMs',
        'dbCompletedAtMs',
        'executionCompletedAtMs',
        'encodedAtMs',
        'completedAtMs',
      ])
        if (w[key] != null) key: r.rel(w[key]! as double),
    };
    final evidence = <String, Object?>{
      'scenario': scenario.label,
      'level': level.name,
      'planScale': scale,
      'durationMs': plan.durationMs.toDouble(),
      'plan': plan.toJson(),
      'deployment': deployment,
      'sessions': [for (final s in _sessions) s.spec.toJson()],
      'publications': publications,
      'completedRefreshes': completed,
      'requests': requests,
      'reconnects': reconnects,
      'writes': [for (final w in r.writes) relWrite(w)],
      'failedWrites': [for (final w in r.failedWrites) relWrite(w)],
      'unfinishedWrites': [
        for (final w
            in window['unfinishedWrites']! as List<Map<String, Object?>>)
          relWrite(w),
      ],
      'failedRefreshes': [
        for (final f in r.failedRefreshes)
          {
            ...f,
            for (final key in ['requestedAtMs', 'completedAtMs'])
              key: r.rel(f[key]! as double),
          },
      ],
      'hints': r.hints,
      'counters': {
        'fullRequests': r.fullRequests,
        'writeRequests': window['writeRequests'],
        'followerResponses': r.followers,
        'retryLaterResponses': r.failedRefreshes
            .where((f) => f['retryAfterMs'] != null)
            .length,
        'capturedBeforeFirstPublication': capturedBeforeFirstPublication,
        'responsesWithoutComputation': withoutComputation,
      },
    };
    evidence['summary'] = summarizeD8Run(evidence).toJson();
    return evidence;
  }

  /// Stops the workers and returns their final counters.
  Future<List<Map<String, Object?>>> close() async {
    for (final s in _sessions) {
      s.policy.cancel();
    }
    for (var w = 0; w < _workers.length; w++) {
      _port(w).send({'type': 'stop'});
    }
    await _until(
      () => _stopped.length == _workers.length,
      const Duration(minutes: 2),
    );
    await _inboxSub.cancel();
    _inbox.close();
    await _publisher.close();
    return _stopped;
  }
}

/// Facts about this process, for the deployment record.
Map<String, Object?> d8ProcessFacts() => {
  'harnessProcessors': Platform.numberOfProcessors,
  'harnessExecutable': Platform.executable.split('/').last,
  'dartVersion': Platform.version.split(' ').first,
};
