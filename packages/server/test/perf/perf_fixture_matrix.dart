import 'dart:convert';
import 'dart:io';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';
import 'perf_recorder.dart';

/// What a [PerfFixtureCase] varies.
enum PerfFixtureFamily {
  /// Visible users with sparse and dense trust.
  trust,

  /// Reciprocal and fallback-score (one-way trusted) peer populations.
  fallbackScore,

  /// Discoverable candidates.
  candidates,

  /// Anchors already placed.
  anchors,

  /// Anchor operations applied in one batch.
  batches,

  /// Aged logs, rejection ratios, multi-worker tabs, trust churn and failure
  /// injection.
  scenarios,
}

/// What a case needs to run one measured attempt.
final class PerfCaseRun {
  PerfCaseRun({
    required this.target,
    required this.db,
    required this.seed,
  });

  final DisposablePgTarget target;
  final TenturaDb db;
  final PerfFixtureSeed seed;

  late final ConstellationFieldCase fieldCase = ConstellationFieldCase(
    ConstellationFieldRepository(db, _ProfileLookup()),
    env: Env(environment: Environment.test),
    logger: Logger('PerfFixtureMatrix'),
  );

  /// An extra session on the disposable database: one more browser tab.
  Future<Connection> openConnection() => Connection.open(
    target.databaseEnv.pgEndpoint,
    settings: target.databaseEnv.pgEndpointSettings,
  );
}

typedef PerfCaseSeed = Future<PerfFixtureSeed> Function(Connection writer);
typedef PerfCaseWork =
    Future<void> Function(PerfCaseRun run, PerfAttemptScope scope, int attempt);

/// One fixture of the matrix: how to seed it, the work its attempts measure
/// and the parameters its report echoes.
final class PerfFixtureCase {
  const PerfFixtureCase._({
    required this.name,
    required this.family,
    required this.parameters,
    required this.seeder,
    required this.worker,
    this.requiresMeritRank = false,
    this.injectsFailures = false,
    this.explains = const [],
  });

  /// Report file name: `build/perf/<name>.json`.
  final String name;
  final PerfFixtureFamily family;
  final Map<String, Object?> parameters;

  /// Whether the work reads (or the seed writes) the MeritRank graph, so the
  /// case runs in the MeritRank phase.
  final bool requiresMeritRank;

  /// Whether failed attempts are the point of the case and are not rethrown.
  final bool injectsFailures;

  /// `EXPLAIN (ANALYZE, BUFFERS, WAL)` captures kept in the report.
  final List<({String label, String sql, bool mutating})> explains;

  /// Creates the fixture's rows (and MeritRank edges) through the writer.
  final PerfCaseSeed seeder;

  /// The work one measured attempt does.
  final PerfCaseWork worker;

  Future<PerfFixtureSeed> seed(Connection writer) => seeder(writer);

  /// Runs [attempts] measured attempts against the seeded database of
  /// [session] and writes `build/perf/<name>.json`.
  Future<File> record({
    required DisposablePgWriterSession session,
    required PerfFixtureSeed seed,
    required int attempts,
  }) async {
    final target = session.target;
    final meter = PerfDbMeter();
    final db = TenturaDb.forTest(
      database: PgDatabase.opened(
        meter.instrument(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
        ),
        enableMigrations: false,
      ).interceptWith(meter),
    );
    try {
      final run = PerfCaseRun(target: target, db: db, seed: seed);
      final recorder = PerfRecorder(
        fixture: name,
        parameters: parameters,
        db: db,
        meter: meter,
        probeConnection: session.writer,
      );
      for (var i = 0; i < attempts; i++) {
        try {
          await recorder.attempt((scope) => worker(run, scope, i));
        } on Object {
          if (!injectsFailures) rethrow;
        }
      }
      for (final explain in explains) {
        await recorder.captureExplain(
          label: explain.label,
          sql: explain.sql,
          mutating: explain.mutating,
        );
      }
      return await recorder.writeReport();
    } finally {
      await db.close();
    }
  }
}

/// The server perf fixture matrix (issue #235 U41): the axes, the cases they
/// make and the check that every case left a full report behind.
abstract final class PerfFixtureMatrix {
  static const visibleUsers = [100, 300, 1000];
  static const fallbackUsers = [0, 10, 100, 1000];
  static const discoverableCandidates = [100, 1000, 10000];
  static const anchors = [0, 20, 200];
  static const batchSizes = [1, 16, 64];

  static const scenarios = [
    'aged_logs',
    'rejection_ratio',
    'multi_worker_tabs',
    'trust_churn',
    'failure_injection',
  ];

  /// The parameter that drives each scenario, which its report must carry.
  static const scenarioEvidenceKeys = {
    'aged_logs': 'logAgeDays',
    'rejection_ratio': 'rejectionRatio',
    'multi_worker_tabs': 'workers',
    'trust_churn': 'churnEdges',
    'failure_injection': 'failureHook',
  };

  static final List<PerfFixtureCase> cases = List.unmodifiable([
    for (final v in visibleUsers) ...[
      _trustCase(PerfFixture.sparseTrust(visibleUsers: v), 'sparse'),
      _trustCase(PerfFixture.denseTrust(visibleUsers: v), 'dense'),
    ],
    for (final u in fallbackUsers) ...[
      _fallbackCase('reciprocal', u),
      _fallbackCase('fallback', u),
    ],
    for (final c in discoverableCandidates) _candidatesCase(c),
    for (final a in anchors) _anchorsCase(a),
    for (final b in batchSizes) _batchCase(b),
    _agedLogsCase,
    _rejectionRatioCase,
    _multiWorkerTabsCase,
    _trustChurnCase,
    _failureInjectionCase,
  ]);

  /// Names of the cases whose `<name>.json` in [directory] is absent or not a
  /// full report: JSON of that fixture with at least one recorded attempt and
  /// the case's parameters.
  static List<String> missingReports(Directory directory) => [
    for (final c in cases)
      if (!_isFullReport(File('${directory.path}/${c.name}.json'), c)) c.name,
  ];
}

bool _isFullReport(File file, PerfFixtureCase c) {
  if (!file.existsSync()) return false;
  try {
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?> || json['fixture'] != c.name) {
      return false;
    }
    final attempts = json['attempts'];
    if (attempts is! Map<String, Object?> ||
        (attempts['total'] as int? ?? 0) < 1) {
      return false;
    }
    final parameters = json['parameters'];
    return parameters is Map<String, Object?> &&
        c.parameters.entries.every(
          (e) => parameters.containsKey(e.key) && parameters[e.key] == e.value,
        );
  } on FormatException {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Cases

PerfFixtureCase _trustCase(PerfFixture fixture, String kind) =>
    PerfFixtureCase._(
      name: fixture.name,
      family: PerfFixtureFamily.trust,
      parameters: {'visibleUsers': fixture.visibleUsers, 'trust': kind},
      requiresMeritRank: true,
      seeder: fixture.seed,
      worker: (run, scope, _) => _fullRead(run, scope),
    );

/// A 100-user sparse field plus [users] more peers the viewer trusts. A
/// `reciprocal` peer trusts back, so visibility needs no further MeritRank
/// call; a `fallback` peer is trusted one way only and costs a fallback score
/// RPC each.
PerfFixtureCase _fallbackCase(String population, int users) =>
    PerfFixtureCase._(
      name: 'fallback_${population == 'fallback' ? 'score' : population}'
          '_u$users',
      family: PerfFixtureFamily.fallbackScore,
      parameters: {
        'visibleUsers': 100,
        'population': population,
        'fallbackUsers': users,
      },
      requiresMeritRank: true,
      seeder: (writer) async {
        final seed = await const PerfFixture.sparseTrust(
          visibleUsers: 100,
        ).seed(writer);
        if (users == 0) return seed;
        await _insertUsers(writer, 'Upg', 1, users);
        await writer.execute(
          Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
SELECT @viewer::text, 'Upg' || lpad(n::text, 9, '0'), 1
FROM generate_series(1, @users::int) n
UNION ALL
SELECT 'Upg' || lpad(n::text, 9, '0'), @viewer::text, 1
FROM generate_series(1, @users::int) n
WHERE @reciprocal::boolean
'''),
          parameters: {
            'viewer': seed.viewerId,
            'users': users,
            'reciprocal': population == 'reciprocal',
          },
        );
        // A reciprocal peer is linked both ways with the viewer; a fallback
        // peer only reaches the viewer's field through one outgoing edge, so
        // the viewer's own score list does not carry it.
        await writer.execute(
          Sql.named('''
SELECT mr_put_edge(e.src, e.dst, 0.75::double precision, ''::text, 0)
FROM (
  SELECT @viewer::text AS src, 'Upg' || lpad(n::text, 9, '0') AS dst
  FROM generate_series(1, @users::int) n WHERE @reciprocal::boolean
  UNION ALL
  SELECT 'Upg' || lpad(n::text, 9, '0'), @viewer::text
  FROM generate_series(1, @users::int) n WHERE @reciprocal::boolean
  UNION ALL
  SELECT 'Upg' || lpad(n::text, 9, '0'), @peer::text
  FROM generate_series(1, @users::int) n WHERE NOT @reciprocal::boolean
) e
'''),
          parameters: {
            'viewer': seed.viewerId,
            'peer': seed.peerIds.first,
            'users': users,
            'reciprocal': population == 'reciprocal',
          },
        );
        return seed;
      },
      worker: (run, scope, _) => _fullRead(run, scope),
    );

const _candidateCap = 1000;

const _candidateScanSql = '''
SELECT b.id, b.user_id
FROM public.beacon b
WHERE b.is_discoverable
  AND b.kind = 0
  AND b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
  AND b.user_id <> '%VIEWER%'
ORDER BY b.user_id, b.id
LIMIT ${_candidateCap + 1}
''';

PerfFixtureCase _candidatesCase(int candidates) {
  final viewer = _id('Upc', 0);
  return PerfFixtureCase._(
    name: 'candidates_c$candidates',
    family: PerfFixtureFamily.candidates,
    parameters: {'candidates': candidates, 'cap': _candidateCap},
    explains: [
      (
        label: 'candidate_scan',
        sql: _candidateScanSql.replaceAll('%VIEWER%', viewer),
        mutating: false,
      ),
    ],
    seeder: (writer) async {
      await _insertUsers(writer, 'Upc', 0, 100);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, is_discoverable)
SELECT 'Bpc' || lpad(n::text, 9, '0'),
       'Upc' || lpad((n % 100 + 1)::text, 9, '0'),
       'perf ' || n, '', 0, now(), true
FROM generate_series(1, @candidates::int) n
'''),
        parameters: {'candidates': candidates},
      );
      await writer.execute('ANALYZE public.beacon');
      return PerfFixtureSeed(
        viewerId: viewer,
        peerIds: [for (var n = 1; n <= 100; n++) _id('Upc', n)],
      );
    },
    worker: (run, scope, _) => scope.execution(
      () => run.db
          .customSelect(
            _candidateScanSql.replaceAll('%VIEWER%', run.seed.viewerId),
          )
          .get(),
    ),
  );
}

PerfFixtureCase _anchorsCase(int anchors) => PerfFixtureCase._(
  name: 'anchors_a$anchors',
  family: PerfFixtureFamily.anchors,
  parameters: {'anchors': anchors},
  seeder: (writer) => _seedAnchors(writer, placed: anchors, spare: 1),
  // The ANCHORS read, then one placement and its removal.
  worker: (run, scope, _) => scope.execution(
    () => run.db.transaction(() async {
      await _lockCursor(run.db, run.seed.viewerId);
      await run.db
          .customSelect(
            'SELECT id, person_id, x_units, y_units, revision '
            r'FROM public.constellation_anchor WHERE viewer_id = $1 '
            'ORDER BY id',
            variables: [Variable.withString(run.seed.viewerId)],
          )
          .get();
      await _upsertAnchor(run.db, run.seed.viewerId, run.seed.peerIds.last);
      await run.db.customStatement(
        'DELETE FROM public.constellation_anchor '
        r'WHERE viewer_id = $1 AND person_id = $2',
        [run.seed.viewerId, run.seed.peerIds.last],
      );
    }),
  ),
);

PerfFixtureCase _batchCase(int batch) => PerfFixtureCase._(
  name: 'batch_b$batch',
  family: PerfFixtureFamily.batches,
  parameters: {'batch': batch},
  seeder: (writer) => _seedAnchors(writer, placed: 0, spare: 64),
  worker: (run, scope, _) => scope.execution(
    () => run.db.transaction(() async {
      await _lockCursor(run.db, run.seed.viewerId);
      for (final person in run.seed.peerIds.take(batch)) {
        await _upsertAnchor(run.db, run.seed.viewerId, person);
      }
    }),
  ),
);

const _agedLogDays = 30;
const _agedLogRows = 20000;

final _agedLogsCase = PerfFixtureCase._(
  name: 'scenario_aged_logs',
  family: PerfFixtureFamily.scenarios,
  parameters: {
    'scenario': 'aged_logs',
    'logAgeDays': _agedLogDays,
    'logRows': _agedLogRows,
  },
  explains: [
    (
      label: 'purge_aged_op_log',
      sql:
          'DELETE FROM public.constellation_anchor_op_log '
          "WHERE created_at < now() - interval '1 day'",
      mutating: true,
    ),
  ],
  seeder: (writer) async {
    final seed = await _seedAnchors(writer, placed: 0, spare: 1);
    await writer.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor_op_log
  (viewer_id, client_op_id, fingerprint, result, revision, created_at)
SELECT @viewer::text, 'old-' || n, decode(repeat('ab', 32), 'hex'),
       '{}'::jsonb, n, now() - make_interval(days => @days::int)
FROM generate_series(1, @rows::int) n
'''),
      parameters: {
        'viewer': seed.viewerId,
        'days': _agedLogDays,
        'rows': _agedLogRows,
      },
    );
    await writer.execute('ANALYZE public.constellation_anchor_op_log');
    return seed;
  },
  // Idempotency probe against the aged log, then a fresh op recorded.
  worker: (run, scope, attempt) => scope.execution(
    () => run.db.transaction(() async {
      final viewer = run.seed.viewerId;
      await _lockCursor(run.db, viewer);
      for (final op in ['old-${attempt + 1}', 'new-$attempt']) {
        await run.db
            .customSelect(
              'SELECT revision FROM public.constellation_anchor_op_log '
              r'WHERE viewer_id = $1 AND client_op_id = $2',
              variables: [
                Variable.withString(viewer),
                Variable.withString(op),
              ],
            )
            .get();
      }
      await _upsertAnchor(run.db, viewer, run.seed.peerIds.first);
      await run.db.customStatement(
        'INSERT INTO public.constellation_anchor_op_log '
        '(viewer_id, client_op_id, fingerprint, result, revision) '
        r"VALUES ($1, $2, decode(repeat('cd', 32), 'hex'), '{}'::jsonb, 1) "
        'ON CONFLICT DO NOTHING',
        [viewer, 'new-$attempt'],
      );
    }),
  ),
);

const _rejectionRatio = 0.25;
const _rejectionBatch = 64;

final _rejectionRatioCase = PerfFixtureCase._(
  name: 'scenario_rejection_ratio',
  family: PerfFixtureFamily.scenarios,
  parameters: {
    'scenario': 'rejection_ratio',
    'rejectionRatio': _rejectionRatio,
    'batch': _rejectionBatch,
  },
  seeder: (writer) async {
    final seed = await _seedAnchors(writer, placed: 0, spare: _rejectionBatch);
    // The targets whose watermark is already ahead of the batch's revision.
    await writer.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor_target_watermark
  (viewer_id, target_kind, target_id, revision)
SELECT @viewer::text, 'person', p, 1000000
FROM unnest(@people::text[]) WITH ORDINALITY t(p, i)
WHERE i <= @rejected::int
'''),
      parameters: {
        'viewer': seed.viewerId,
        'people': seed.peerIds,
        'rejected': (_rejectionBatch * _rejectionRatio).round(),
      },
    );
    return seed;
  },
  worker: (run, scope, _) => scope.execution(
    () => run.db.transaction(() async {
      final viewer = run.seed.viewerId;
      await _lockCursor(run.db, viewer);
      var rejected = 0;
      for (final person in run.seed.peerIds) {
        final watermark = await run.db
            .customSelect(
              'SELECT revision FROM '
              'public.constellation_anchor_target_watermark '
              r"WHERE viewer_id = $1 AND target_kind = 'person' "
              r'AND target_id = $2',
              variables: [
                Variable.withString(viewer),
                Variable.withString(person),
              ],
            )
            .getSingleOrNull();
        // Every operation carries base revision 1.
        if (watermark != null && watermark.read<BigInt>('revision') >= BigInt.one) {
          rejected++;
          continue;
        }
        await _upsertAnchor(run.db, viewer, person);
      }
      if (rejected != (_rejectionBatch * _rejectionRatio).round()) {
        throw StateError('rejected $rejected operations, not the seeded share');
      }
    }),
  ),
);

const _tabWorkers = 4;

final _multiWorkerTabsCase = PerfFixtureCase._(
  name: 'scenario_multi_worker_tabs',
  family: PerfFixtureFamily.scenarios,
  parameters: {'scenario': 'multi_worker_tabs', 'workers': _tabWorkers},
  seeder: (writer) => _seedAnchors(writer, placed: 0, spare: _tabWorkers),
  // Each tab places an anchor under the same viewer cursor lock: one through
  // the metered database, the others on sessions of their own.
  worker: (run, scope, _) => scope.execution(() async {
    final viewer = run.seed.viewerId;
    final people = run.seed.peerIds;
    final tabs = [
      for (var w = 1; w < _tabWorkers; w++) await run.openConnection(),
    ];
    try {
      await Future.wait([
        run.db.transaction(() async {
          await _lockCursor(run.db, viewer);
          await _upsertAnchor(run.db, viewer, people[0]);
        }),
        for (var w = 1; w < _tabWorkers; w++)
          tabs[w - 1].runTx((tx) async {
            await tx.execute(
              Sql.named(
                'SELECT 1 FROM public.constellation_anchor_cursor '
                'WHERE viewer_id = @viewer FOR UPDATE',
              ),
              parameters: {'viewer': viewer},
            );
            await tx.execute(
              Sql.named(_upsertAnchorNamedSql),
              parameters: {'viewer': viewer, 'person': people[w]},
            );
          }),
      ]);
    } finally {
      for (final tab in tabs) {
        await tab.close();
      }
    }
  }),
);

const _churnEdges = 50;

final _trustChurnCase = PerfFixtureCase._(
  name: 'scenario_trust_churn',
  family: PerfFixtureFamily.scenarios,
  parameters: {'scenario': 'trust_churn', 'churnEdges': _churnEdges},
  requiresMeritRank: true,
  seeder: const PerfFixture.sparseTrust(visibleUsers: 100).seed,
  // Rewrite edges of the peer ring, then read the field they changed.
  worker: (run, scope, attempt) async {
    await scope.execution(
      () => run.db.customSelect(
        'SELECT mr_put_edge( '
        "'Upf' || lpad(n::text, 9, '0'), "
        "'Upf' || lpad((n % 99 + 1)::text, 9, '0'), "
        r"$1::double precision, ''::text, 0) AS edge "
        r'FROM generate_series(1, $2::int) n',
        variables: [
          Variable.withReal(attempt.isEven ? 0.5 : 0.9),
          Variable.withInt(_churnEdges),
        ],
      ).get(),
    );
    await _fullRead(run, scope);
  },
);

const _failureHook = 'statement_timeout';

final _failureInjectionCase = PerfFixtureCase._(
  name: 'scenario_failure_injection',
  family: PerfFixtureFamily.scenarios,
  parameters: {'scenario': 'failure_injection', 'failureHook': _failureHook},
  injectsFailures: true,
  seeder: (writer) => _seedAnchors(writer, placed: 0, spare: 1),
  // Every other attempt runs under a 1 ms statement timeout and fails.
  worker: (run, scope, attempt) => scope.execution(
    () => run.db.transaction(() async {
      if (attempt.isEven) {
        await run.db.customStatement("SET LOCAL statement_timeout = '1ms'");
        await run.db.customStatement('SELECT pg_sleep(0.2)');
      }
      await _lockCursor(run.db, run.seed.viewerId);
      await _upsertAnchor(run.db, run.seed.viewerId, run.seed.peerIds.first);
    }),
  ),
);

// ---------------------------------------------------------------------------
// Shared seeding and work

String _id(String prefix, int n) => '$prefix${n.toString().padLeft(9, '0')}';

Future<void> _insertUsers(Connection writer, String prefix, int from, int to) =>
    writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT @prefix::text || lpad(n::text, 9, '0'), 'perf ' || n,
       'pk-' || @prefix::text || n
FROM generate_series(@from::int, @to::int) n
'''),
      parameters: {'prefix': prefix, 'from': from, 'to': to},
    );

/// A viewer with a cursor row, [placed] anchors on the first people and
/// [spare] more people with none; `peerIds` lists all of them.
Future<PerfFixtureSeed> _seedAnchors(
  Connection writer, {
  required int placed,
  required int spare,
}) async {
  final people = placed + spare;
  await _insertUsers(writer, 'Upa', 0, people);
  await writer.execute(
    Sql.named(
      'INSERT INTO public.constellation_anchor_cursor (viewer_id) '
      'VALUES (@viewer)',
    ),
    parameters: {'viewer': _id('Upa', 0)},
  );
  if (placed > 0) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units, coordinate_space_version,
   revision, placed_at)
SELECT 'Apa' || lpad(n::text, 9, '0'), @viewer::text,
       'Upa' || lpad(n::text, 9, '0'),
       (n % 20) - 10, (n % 7) - 3, 1, 0, now()
FROM generate_series(1, @placed::int) n
'''),
      parameters: {'viewer': _id('Upa', 0), 'placed': placed},
    );
  }
  return PerfFixtureSeed(
    viewerId: _id('Upa', 0),
    peerIds: [for (var n = 1; n <= people; n++) _id('Upa', n)],
  );
}

Future<void> _lockCursor(TenturaDb db, String viewerId) => db.customStatement(
  'SELECT viewer_id FROM public.constellation_anchor_cursor '
  r'WHERE viewer_id = $1 FOR UPDATE',
  [viewerId],
);

const _upsertAnchorNamedSql = '''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units, coordinate_space_version,
   revision, placed_at)
VALUES ('A' || substr(md5(@viewer::text || @person::text), 1, 20),
        @viewer::text, @person::text, 1.5, -2.5, 1, 0, now())
ON CONFLICT (viewer_id, person_id) WHERE person_id IS NOT NULL
DO UPDATE SET x_units = excluded.x_units + 0.5, y_units = excluded.y_units
''';

Future<void> _upsertAnchor(TenturaDb db, String viewerId, String personId) =>
    db.customStatement(
      _upsertAnchorNamedSql
          .replaceAll('@viewer::text', r'$1::text')
          .replaceAll('@person::text', r'$2::text'),
      [viewerId, personId],
    );

/// Today's FULL read through the production use case and wire encoding.
Future<void> _fullRead(PerfCaseRun run, PerfAttemptScope scope) async {
  final snapshot = await scope.execution(
    () => run.fieldCase.readSnapshot(
      viewerId: run.seed.viewerId,
      context: '',
      params: (
        filters: ConstellationFieldMembershipFilters.defaults,
        projection: ConstellationProjection.full,
      ),
    ),
  );
  jsonEncode(constellationFieldToGqlMap(snapshot));
}

/// A peer without a profile is dropped from the snapshot, so every fixture
/// user gets one for the payload to carry them.
final class _ProfileLookup implements UserProfileBatchLookup {
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
