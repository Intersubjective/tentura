// Disposable Postgres benchmark for GATE-14.1 (UNIT 02).
// Run: cd packages/server && dart run tool/constellation_read_wall_benchmark.dart
// Targets ONLY a throwaway tentura_test_constellation_perf_* database — never shared postgres data.

import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

const _viewerId = 'Uconstviewer';
const _profileTargetId = 'Uconst00001';
const _userCount = 5000;
const _beaconCount = 50000;
const _peerCount = 200;
const _warmupRuns = 2;
const _timedRuns = 10;

// Verbatim from docs/plans/constellation-implementation-plan.md §0.1
const _m0160 = r'''
ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS is_discoverable boolean;
UPDATE public.beacon SET is_discoverable = true WHERE is_discoverable IS NULL;
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET DEFAULT true;
ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET NOT NULL;

CREATE INDEX IF NOT EXISTS beacon_discoverable_author_idx
  ON public.beacon (user_id)
  WHERE is_discoverable AND status IN (0, 7, 8) AND published_at IS NOT NULL;
''';

const _m0161Reciprocal = r'''
CREATE OR REPLACE FUNCTION public.person_reciprocal_explicit_trust(
  a_id text, b_id text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = a_id AND vu.object = b_id AND vu.amount > 0)
  AND EXISTS (
    SELECT 1 FROM public.vote_user vu
    WHERE vu.subject = b_id AND vu.object = a_id AND vu.amount > 0);
$$;
''';

const _m0161Mutual = r'''
CREATE OR REPLACE FUNCTION public.person_are_mutually_visible(
  a_id text, b_id text, ctx text
) RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT CASE
  WHEN nullif(trim(coalesce(a_id, '')), '') IS NULL THEN false
  WHEN nullif(trim(coalesce(b_id, '')), '') IS NULL THEN false
  WHEN a_id = b_id THEN false
  WHEN public.person_reciprocal_explicit_trust(a_id, b_id) THEN true
  WHEN public.person_is_mutually_visible(a_id, b_id, coalesce(ctx, '')) THEN true
  ELSE public.person_is_mutually_visible(b_id, a_id, coalesce(ctx, ''))
END;
$$;
''';

const _m0161Peers = r'''
CREATE OR REPLACE FUNCTION public.person_visible_peers_symmetric(
  viewer_id text, ctx text
) RETURNS TABLE (peer_id text) LANGUAGE sql STABLE AS $$
WITH n AS (
  SELECT nullif(trim(coalesce(viewer_id, '')), '') AS v_id,
         coalesce(ctx, '')                          AS v_ctx
)
SELECT c.peer_id::text
FROM n
CROSS JOIN public.person_visibility_peers(n.v_id, n.v_ctx) c
WHERE n.v_id IS NOT NULL
  AND c.peer_id::text <> n.v_id
  AND CASE
        WHEN c.is_mutually_visible THEN true
        ELSE public.person_is_mutually_visible(c.peer_id::text, n.v_id, n.v_ctx)
      END;
$$;
''';

const _m0162 = r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    WHEN b.is_discoverable
      AND b.status IN (0, 7, 8)
      AND b.published_at IS NOT NULL
      AND b.user_id IS NOT NULL
      AND public.person_are_mutually_visible(p_viewer_id, b.user_id, '')
      THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''';

const _m0163 = r'''
CREATE OR REPLACE FUNCTION public.constellation_trust_edges(
  p_viewer_id text,
  p_ctx       text,
  node_ids    text[]
) RETURNS TABLE (src text, dst text, tier smallint)
  LANGUAGE sql STABLE AS $$
WITH viewer AS (
  SELECT nullif(trim(coalesce(p_viewer_id, '')), '') AS id, coalesce(p_ctx, '') AS ctx
),
visible AS (
  SELECT s.peer_id::text AS id
  FROM viewer v
  CROSS JOIN public.person_visible_peers_symmetric(v.id, v.ctx) s
  WHERE v.id IS NOT NULL
),
allowed AS (
  SELECT DISTINCT n AS id
  FROM viewer v
  CROSS JOIN unnest(node_ids) AS n
  WHERE v.id IS NOT NULL
    AND nullif(trim(coalesce(n, '')), '') IS NOT NULL
    AND (n = v.id OR n IN (SELECT id FROM visible))
    AND NOT public.block_hides(v.id, n)
),
t1 AS (
  SELECT vu.subject::text AS src, vu.object::text AS dst
  FROM public.vote_user vu
  INNER JOIN allowed a ON a.id = vu.subject
  INNER JOIN allowed b ON b.id = vu.object
  WHERE vu.amount > 0 AND vu.subject <> vu.object
    AND NOT public.block_hides(vu.subject, vu.object)
),
t2 AS (
  SELECT e.subject::text AS src, e.object::text AS dst
  FROM public.user_trust_edge e
  INNER JOIN allowed a ON a.id = e.subject
  INNER JOIN allowed b ON b.id = e.object
  WHERE e.prev_sent_weight > 0 AND e.subject <> e.object
    AND NOT public.block_hides(e.subject, e.object)
)
SELECT t1.src, t1.dst, 1::smallint FROM t1
UNION ALL
SELECT t2.src, t2.dst, 2::smallint FROM t2
WHERE NOT EXISTS (SELECT 1 FROM t1 WHERE t1.src = t2.src AND t1.dst = t2.dst);
$$;
''';

Future<void> main() async {
  final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
  final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
  final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
  final adminDb = Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
  final dbName =
      'tentura_test_constellation_perf_${DateTime.timestamp().microsecondsSinceEpoch}';

  Env envFor(String database) => Env(
    environment: Environment.test,
    pgHost: host,
    pgPort: port,
    pgDatabase: database,
    pgUsername: username,
    pgPassword: password,
    printEnv: false,
    isDebugModeOn: false,
  );

  final adminEnv = envFor(adminDb);
  final targetEnv = envFor(dbName);

  stdout.writeln('GATE-14.1 benchmark — disposable database: $dbName');

  final admin = await Connection.open(
    adminEnv.pgEndpoint,
    settings: ConnectionSettings(
      sslMode: adminEnv.pgEndpointSettings.sslMode,
      queryTimeout: const Duration(hours: 2),
    ),
  );
  try {
    await admin.execute('DROP DATABASE IF EXISTS $dbName WITH (FORCE)');
    await admin.execute('CREATE DATABASE $dbName');
  } finally {
    await admin.close();
  }

  final conn = await Connection.open(
    targetEnv.pgEndpoint,
    settings: ConnectionSettings(
      sslMode: targetEnv.pgEndpointSettings.sslMode,
      queryTimeout: const Duration(hours: 2),
    ),
  );
  try {
    await conn.execute('SET check_function_bodies = false');
    await conn.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
    await migrateDbSchema(conn);
    await _seedFixture(conn);
    await conn.execute('ANALYZE');

    final before = await _runSuite(conn, label: 'before_m0162');
    await _applyM0160(conn);
    await _applyM0161(conn);
    await conn.execute(_m0162);
    await conn.execute('ANALYZE');
    final after = await _runSuite(conn, label: 'after_m0162');
    await conn.execute(_m0163);

    final shortCircuit = await _measureShortCircuit(conn);
    final mrUnavailable = await _measureMeritRankUnavailable(host, port, conn);

    final nodeIds = await _fetchConstellationNodeIds(conn);
    final fieldBaseline = await _runFieldSuite(conn, nodeIds);

    final output = {
      'database': dbName,
      'fixture': {
        'users': _userCount,
        'beacons': _beaconCount,
        'viewer': _viewerId,
        'symmetric_peers': shortCircuit['symmetric_peer_count'],
        'mean_vote_out_degree': '~4',
      },
      'budget_ms_p95_delta_max': 150,
      'before_m0162': before,
      'after_m0162': after,
      'short_circuit': shortCircuit,
      'meritrank_unavailable': mrUnavailable,
      'constellation_field_baseline': fieldBaseline,
      'decision_inputs': _decisionInputs(before, after),
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
  } finally {
    await conn.close();
    final drop = await Connection.open(
      adminEnv.pgEndpoint,
      settings: ConnectionSettings(
        sslMode: adminEnv.pgEndpointSettings.sslMode,
        queryTimeout: const Duration(hours: 2),
      ),
    );
    try {
      await drop.execute('DROP DATABASE IF EXISTS $dbName WITH (FORCE)');
    } finally {
      await drop.close();
    }
  }
}

Map<String, Object?> _decisionInputs(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  final rows = <Map<String, Object?>>[];
  var anyExceeds = false;
  for (final key in before.keys) {
    if (key == 'label') continue;
    final b = before[key] as Map<String, dynamic>;
    final a = after[key] as Map<String, dynamic>;
    final delta = (a['p95_ms'] as num) - (b['p95_ms'] as num);
    final exceeds = delta > 150;
    if (exceeds) anyExceeds = true;
    rows.add({
      'query': key,
      'p95_before_ms': b['p95_ms'],
      'p95_after_ms': a['p95_ms'],
      'delta_p95_ms': delta,
      'within_budget': !exceeds,
    });
  }
  return {
    'gate_decision': anyExceeds ? 'b' : 'a',
    'per_query': rows,
  };
}

Future<void> _applyM0161(Connection conn) async {
  await conn.execute(_m0161Reciprocal);
  await conn.execute(_m0161Mutual);
  await conn.execute(_m0161Peers);
}

Future<void> _applyM0160(Connection conn) async {
  await conn.execute(
    'ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS is_discoverable boolean',
  );
  await conn.execute(
    'UPDATE public.beacon SET is_discoverable = true WHERE is_discoverable IS NULL',
  );
  await conn.execute(
    'ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET DEFAULT true',
  );
  await conn.execute(
    'ALTER TABLE public.beacon ALTER COLUMN is_discoverable SET NOT NULL',
  );
  await conn.execute('''
CREATE INDEX IF NOT EXISTS beacon_discoverable_author_idx
  ON public.beacon (user_id)
  WHERE is_discoverable AND status IN (0, 7, 8) AND published_at IS NOT NULL
''');
}

Future<void> _seedFixture(Connection conn) async {
  stdout.writeln('Seeding fixture…');
  const ts = '2026-01-01T00:00:00Z';

  await conn.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
SELECT
  'Uconst' || lpad(gs::text, 5, '0'),
  'user-' || gs::text,
  md5('pk-' || gs::text) || md5('pk2-' || gs::text),
  '$ts'::timestamptz,
  '$ts'::timestamptz
FROM generate_series(1, $_userCount) AS gs
''');

  await conn.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (
  '$_viewerId',
  'viewer',
  md5('pk-viewer') || md5('pk2-viewer'),
  '$ts',
  '$ts'
)
ON CONFLICT (id) DO NOTHING
''');

  // Mean out-degree ~4: each user trusts next 4 users (mod ring).
  await conn.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT
  'Uconst' || lpad(s::text, 5, '0'),
  'Uconst' || lpad(((s + off - 1) % $_userCount + 1)::text, 5, '0'),
  1,
  '$ts'::timestamptz,
  '$ts'::timestamptz
FROM generate_series(1, $_userCount) AS s
CROSS JOIN generate_series(1, 4) AS off
''');

  // Viewer symmetric explicit-trust peers (~200).
  await conn.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT '$_viewerId', 'Uconst' || lpad(gs::text, 5, '0'), 1, '$ts', '$ts'
FROM generate_series(1, $_peerCount) AS gs
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
  await conn.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
SELECT 'Uconst' || lpad(gs::text, 5, '0'), '$_viewerId', 1, '$ts', '$ts'
FROM generate_series(1, $_peerCount) AS gs
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

  // MeritRank publish: bulk-load the full vote_user graph (same path as m0061).
  final mrInit = Stopwatch()..start();
  await conn.execute('SELECT public.meritrank_init()');
  mrInit.stop();
  stdout.writeln('meritrank_init(): ${mrInit.elapsedMilliseconds}ms');
  await conn.execute(r'SELECT public.mr_bump_publish_epoch()');

  // 50k published active beacons spread across authors.
  await conn.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
)
SELECT
  'Bconst' || lpad(gs::text, 6, '0'),
  'Uconst' || lpad(((gs - 1) % $_userCount + 1)::text, 5, '0'),
  'beacon ' || gs::text,
  'desc',
  CASE WHEN gs % 17 = 0 THEN 7 WHEN gs % 23 = 0 THEN 8 ELSE 0 END,
  '$ts'::timestamptz,
  '$ts'::timestamptz,
  '$ts'::timestamptz
FROM generate_series(1, $_beaconCount) AS gs
''');

  // Inbox rows for viewer (forwarded beacons).
  await conn.execute('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, context, forward_count, latest_forward_at, status
)
SELECT
  '$_viewerId',
  'Bconst' || lpad(gs::text, 6, '0'),
  '',
  1,
  '$ts'::timestamptz,
  1
FROM generate_series(1, 500) AS gs
''');

  // Profile target forward edge sample.
  await conn.execute('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
)
SELECT
  'Fconst' || lpad(gs::text, 6, '0'),
  'Bconst' || lpad((1000 + gs)::text, 6, '0'),
  '$_viewerId',
  '$_profileTargetId',
  '$ts'::timestamptz
FROM generate_series(1, 50) AS gs
''');

  // Attention outbox rows (beacon_content policy).
  await conn.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload,
  suppression_class, access_policy
)
SELECT
  'Nconst' || lpad(gs::text, 6, '0'),
  '$_viewerId',
  'beacon',
  'beaconStatusChanged',
  'normal',
  'title',
  'body',
  '/attention',
  'dedup-Nconst' || lpad(gs::text, 6, '0'),
  '$ts'::timestamptz,
  'Bconst' || lpad((2000 + gs)::text, 6, '0'),
  'source-Nconst' || lpad(gs::text, 6, '0'),
  'inbox',
  'beacon_status_changed',
  '{"eventType":"fixture"}'::jsonb,
  'standard',
  'beacon_content'
FROM generate_series(1, 200) AS gs
''');

  // Image metadata rows.
  await conn.execute('''
INSERT INTO public.image (id, hash, height, width, created_at, author_id)
SELECT
  ('00000000-0000-4000-8000-' || lpad(to_hex(gs), 12, '0'))::uuid,
  md5('img-' || gs::text),
  100,
  100,
  '$ts'::timestamptz,
  'Uconst' || lpad(((gs - 1) % $_userCount + 1)::text, 5, '0')
FROM generate_series(1, 100) AS gs
''');
  await conn.execute('''
INSERT INTO public.beacon_image (beacon_id, image_id, position)
SELECT
  'Bconst' || lpad(gs::text, 6, '0'),
  ('00000000-0000-4000-8000-' || lpad(to_hex(((gs - 1) % 100) + 1), 12, '0'))::uuid,
  0
FROM generate_series(1, 100) AS gs
''');
}

Future<Map<String, dynamic>> _runSuite(
  Connection conn, {
  required String label,
}) async {
  final queries = _benchmarkQueries();
  final out = <String, dynamic>{'label': label};
  for (final entry in queries.entries) {
    out[entry.key] = await _measureQuery(conn, entry.value);
  }
  return out;
}

Map<String, String> _benchmarkQueries() => {
  'hasura_beacon_row_filter': '''
SELECT b.id, b.title, b.user_id, b.status, b.updated_at
FROM public.beacon b
WHERE public.beacon_can_read_content(b.id, @viewer)
ORDER BY b.updated_at DESC
''',
  'my_work_authored_list': '''
SELECT b.id, b.title, b.status, b.updated_at
FROM public.beacon b
WHERE b.user_id = @viewer
  AND b.status <> 2
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_archived ba
    WHERE ba.beacon_id = b.id AND ba.user_id = @viewer
  )
  AND public.beacon_can_read_content(b.id, @viewer)
ORDER BY b.updated_at DESC
''',
  'inbox_list': '''
SELECT ii.beacon_id, ii.latest_forward_at, ii.status, b.title
FROM public.inbox_item ii
INNER JOIN public.beacon b ON b.id = ii.beacon_id
WHERE ii.user_id = @viewer
  AND public.beacon_can_read_content(b.id, @viewer)
ORDER BY ii.latest_forward_at DESC
''',
  'profile_shared_forwarded': '''
SELECT fe.id, fe.beacon_id, fe.created_at, b.title
FROM public.beacon_forward_edge fe
INNER JOIN public.beacon b ON b.id = fe.beacon_id
WHERE fe.sender_id = @viewer
  AND fe.recipient_id = @profileTarget
  AND public.beacon_can_read_content(b.id, @viewer)
ORDER BY fe.created_at DESC
''',
  'attention_intent_batch': '''
SELECT receipt_id, tombstone_copy
FROM public.visible_attention_receipts(@viewer)
''',
  'beacon_image_metadata': '''
SELECT bi.beacon_id, bi.image_id, bi.position, i.hash, i.width, i.height
FROM public.beacon_image bi
INNER JOIN public.image i ON i.id = bi.image_id
INNER JOIN public.beacon b ON b.id = bi.beacon_id
WHERE public.beacon_can_read_content(b.id, @viewer)
''',
};

/// Bounds every probe at [_probeTimeoutMs] so a query the post-m0162
/// discoverability branch makes catastrophically slow (observed: >16min for a
/// single unindexed 50k-row scan under `person_are_mutually_visible`, which
/// recomputes `person_visibility_peers(viewer)` from scratch per row) cannot
/// again consume the whole worker session with zero measurement produced.
/// A single probe already answers the only question the decision rule needs
/// ("does this blow the +150ms budget, and by how much") — repeating a
/// multi-minute query 12 times to get a percentile is not additional signal,
/// it is 12x the wall-clock cost for the same answer. Only queries that come
/// back fast get the full warmup+timed-run treatment, so cheap queries keep
/// their percentile fidelity.
const _probeTimeoutMs = 8000;
const _slowThresholdMs = 1500;

Future<Map<String, dynamic>> _measureQuery(
  Connection conn,
  String sql,
) async {
  final params = <String, dynamic>{'viewer': _viewerId};
  if (sql.contains('@profileTarget')) {
    params['profileTarget'] = _profileTargetId;
  }

  await conn.execute("SET statement_timeout = '${_probeTimeoutMs}ms'");
  double? probeMs;
  bool probeTimedOut = false;
  try {
    final sw = Stopwatch()..start();
    await conn.execute(Sql.named(sql), parameters: params);
    sw.stop();
    probeMs = sw.elapsedMicroseconds / 1000.0;
  } catch (_) {
    probeTimedOut = true;
  }

  Map<String, dynamic> result;
  if (probeTimedOut || (probeMs != null && probeMs > _slowThresholdMs)) {
    // Slow (or already timed out) — do not repeat. One capped sample is
    // sufficient evidence for the a/b decision; report it as such.
    final capped = probeTimedOut ? _probeTimeoutMs.toDouble() : probeMs!;
    result = {
      'p50_ms': capped,
      'p95_ms': capped,
      'runs': 1,
      'single_sample_reason': probeTimedOut
          ? 'exceeded ${_probeTimeoutMs}ms statement_timeout — reported value '
                'is the cap, true latency is >= this'
          : 'first sample exceeded ${_slowThresholdMs}ms fast-path threshold; '
                'repeated sampling skipped to bound benchmark runtime',
    };
  } else {
    // Fast path: full warmup + timed-run methodology for percentile fidelity.
    for (var i = 0; i < _warmupRuns - 1; i++) {
      await conn.execute(Sql.named(sql), parameters: params);
    }
    final samples = <double>[probeMs!];
    for (var i = 0; i < _timedRuns - 1; i++) {
      final sw = Stopwatch()..start();
      await conn.execute(Sql.named(sql), parameters: params);
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
    samples.sort();
    result = {
      'p50_ms': _percentile(samples, 0.50),
      'p95_ms': _percentile(samples, 0.95),
      'runs': _timedRuns,
    };
  }

  try {
    final explain = await conn.execute(
      Sql.named('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) $sql'),
      parameters: params,
    );
    final rawPlan = explain.first.first;
    final List<dynamic> planJson = rawPlan is String
        ? jsonDecode(rawPlan) as List<dynamic>
        : rawPlan is List
        ? rawPlan
        : [rawPlan];
    final plan = planJson.first as Map<String, dynamic>;
    result['explain_planning_ms'] = plan['Planning Time'] as num? ?? 0;
    result['explain_execution_ms'] =
        plan['Plan']?['Actual Total Time'] as num? ?? 0;
    result['rows_examined'] = _extractRowsExamined(
      plan['Plan'] as Map<String, dynamic>?,
    );
    result['row_count'] = plan['Plan']?['Actual Rows'];
  } catch (e) {
    result['explain_error'] =
        'EXPLAIN ANALYZE itself exceeded ${_probeTimeoutMs}ms: $e';
  } finally {
    await conn.execute('SET statement_timeout = 0');
  }

  return result;
}

num _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final idx = (p * (sorted.length - 1)).round();
  return double.parse(sorted[idx].toStringAsFixed(3));
}

int _extractRowsExamined(Map<String, dynamic>? node) {
  if (node == null) return 0;
  var total = (node['Actual Rows'] as num?)?.toInt() ?? 0;
  final plans = node['Plans'] as List<dynamic>?;
  if (plans != null) {
    for (final child in plans) {
      total += _extractRowsExamined(child as Map<String, dynamic>);
    }
  }
  return total;
}

Future<Map<String, dynamic>> _measureShortCircuit(Connection conn) async {
  await conn.execute("SET statement_timeout = '${_probeTimeoutMs}ms'");
  try {
    final peerCount = await conn.execute(Sql.named('''
SELECT count(*)::int AS c
FROM public.person_visible_peers_symmetric(@viewer, '')
'''), parameters: {'viewer': _viewerId});

    // NOTE: this recomputes person_are_mutually_visible per distinct beacon
    // author (up to one call per beacon row before dedup) — the same cost
    // shape _measureQuery guards against. Capped at _probeTimeoutMs; a
    // timeout here is itself evidence for the gate decision, not a tool bug.
    int totalAuthors;
    try {
      final discoverableAuthors = await conn.execute(Sql.named('''
SELECT count(DISTINCT b.user_id)::int AS c
FROM public.beacon b
WHERE b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
  AND b.user_id IS NOT NULL
  AND b.user_id <> @viewer
  AND public.person_are_mutually_visible(@viewer, b.user_id, '')
'''), parameters: {'viewer': _viewerId});
      totalAuthors = discoverableAuthors.first.first as int;
    } catch (e) {
      return {
        'symmetric_peer_count': peerCount.first.first,
        'discoverable_author_distinct_count': null,
        'discoverable_author_count_error':
            'exceeded ${_probeTimeoutMs}ms statement_timeout: $e',
        'note':
            'Short-circuit hit-rate measurement itself timed out — this is '
            'consistent with the per-row person_are_mutually_visible cost '
            'finding from the main suite, not a separate tool defect.',
      };
    }

    final reciprocalHits = await conn.execute(Sql.named('''
SELECT count(*)::int AS c
FROM (
  SELECT DISTINCT b.user_id AS author_id
  FROM public.beacon b
  WHERE b.status IN (0, 7, 8)
    AND b.published_at IS NOT NULL
    AND b.user_id IS NOT NULL
    AND b.user_id <> @viewer
) authors
WHERE public.person_reciprocal_explicit_trust(@viewer, authors.author_id)
'''), parameters: {'viewer': _viewerId});

    final reciprocal = reciprocalHits.first.first as int;
    return {
      'symmetric_peer_count': peerCount.first.first,
      'discoverable_author_distinct_count': totalAuthors,
      'reciprocal_explicit_trust_hits': reciprocal,
      'short_circuit_fraction': totalAuthors == 0
          ? 0
          : reciprocal / totalAuthors,
      'note':
          'Short-circuit hits reciprocal vote_user only; misses multi-hop MR audience and does not bound worst case.',
    };
  } finally {
    await conn.execute('SET statement_timeout = 0');
  }
}

Future<Map<String, dynamic>> _measureMeritRankUnavailable(
  String host,
  int port,
  Connection conn,
) async {
  final results = <String, dynamic>{};
  final queries = _benchmarkQueries();

  // Stop meritrank container if running.
  final stop = await Process.run('docker', ['stop', 'meritrank']);
  stdout.writeln('docker stop meritrank: exit ${stop.exitCode}');

  await Future<void>.delayed(const Duration(seconds: 2));

  // Reading mr_mutual_scores is a local table read, not a live call to the
  // meritrank service, so stopping the container does not make a slow
  // discoverability-branch scan any faster — bound it the same way
  // _measureQuery does, or this loop can hang exactly like the main suite did.
  await conn.execute("SET statement_timeout = '${_probeTimeoutMs}ms'");
  for (final entry in queries.entries) {
    final key = entry.key;
    final params = <String, dynamic>{'viewer': _viewerId};
    if (entry.value.contains('@profileTarget')) {
      params['profileTarget'] = _profileTargetId;
    }
    try {
      final sw = Stopwatch()..start();
      final rows = await conn.execute(
        Sql.named(entry.value),
        parameters: params,
      );
      sw.stop();
      results[key] = {
        'outcome': 'returned',
        'row_count': rows.length,
        'latency_ms': sw.elapsedMilliseconds,
      };
    } catch (e) {
      results[key] = {
        'outcome': 'error_or_timeout',
        'error': e.toString(),
        'note': 'capped at ${_probeTimeoutMs}ms statement_timeout',
      };
    }
  }
  await conn.execute('SET statement_timeout = 0');

  // person_are_mutually_visible on discoverability path
  try {
    final row = await conn.execute(Sql.named('''
SELECT public.beacon_can_read_content(
  (SELECT id FROM public.beacon WHERE user_id <> @viewer LIMIT 1),
  @viewer
) AS allowed
'''), parameters: {'viewer': _viewerId});
    results['discoverability_branch_sample'] = {
      'outcome': 'returned',
      'allowed': row.first.first,
    };
  } catch (e) {
    results['discoverability_branch_sample'] = {
      'outcome': 'error',
      'error': e.toString(),
    };
  }

  final start = await Process.run('docker', ['start', 'meritrank']);
  stdout.writeln('docker start meritrank: exit ${start.exitCode}');
  await Future<void>.delayed(const Duration(seconds: 3));

  // Health check
  final health = await Process.run('docker', [
    'inspect',
    '--format',
    '{{.State.Health.Status}}',
    'meritrank',
  ]);
  results['meritrank_restart_health'] = (health.stdout as String).trim();

  return results;
}

Future<List<String>> _fetchConstellationNodeIds(Connection conn) async {
  final peers = await conn.execute(Sql.named('''
SELECT peer_id::text
FROM public.person_visible_peers_symmetric(@viewer, '')
ORDER BY peer_id
LIMIT 200
'''), parameters: {'viewer': _viewerId});
  final ids = [_viewerId, ...peers.map((r) => r.first as String)];
  return ids;
}

Future<Map<String, dynamic>> _runFieldSuite(
  Connection conn,
  List<String> nodeIds,
) async {
  final peerSql = '''
SELECT peer_id::text
FROM public.person_visible_peers_symmetric(@viewer, '')
ORDER BY peer_id
LIMIT 200
''';
  final edgesSql = '''
SELECT src, dst, tier
FROM public.constellation_trust_edges(@viewer, '', @nodeIds::text[])
''';
  final ownReqSql = '''
SELECT b.id, b.user_id, b.title, b.status
FROM public.beacon b
WHERE b.user_id = @viewer
  AND b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
ORDER BY b.updated_at DESC
LIMIT 150
''';
  final discoverSql = '''
SELECT b.id, b.user_id, b.title, b.status
FROM public.person_visible_peers_symmetric(@viewer, '') p
INNER JOIN public.beacon b ON b.user_id = p.peer_id
WHERE b.user_id <> @viewer
  AND b.is_discoverable
  AND b.status IN (0, 7, 8)
  AND b.published_at IS NOT NULL
  AND NOT public.block_hides(@viewer, b.user_id)
  AND public.beacon_can_read_content(b.id, @viewer)
ORDER BY b.updated_at DESC
LIMIT 150
''';
  final profilesSql = '''
SELECT u.id, u.display_name, u.handle
FROM public."user" u
WHERE u.id = ANY(@ids::text[])
''';

  final peerIds = await conn.execute(
    Sql.named(peerSql),
    parameters: {'viewer': _viewerId},
  );
  final idsForProfiles = peerIds.map((r) => r.first as String).toList();
  idsForProfiles.add(_viewerId);

  return {
    'person_visible_peers_symmetric': await _measureQuery(conn, peerSql),
    'constellation_trust_edges': await _measureQuery(conn, edgesSql.replaceAll(
      '@nodeIds::text[]',
      "ARRAY[${nodeIds.map((id) => "'$id'").join(',')}]",
    )),
    'constellation_field_composed_ms': await _measureComposedField(
      conn,
      peerSql: peerSql,
      edgesSql: edgesSql,
      ownReqSql: ownReqSql,
      discoverSql: discoverSql,
      profilesSql: profilesSql,
      nodeIds: nodeIds,
      profileIds: idsForProfiles,
    ),
  };
}

Future<Map<String, dynamic>> _measureComposedField(
  Connection conn, {
  required String peerSql,
  required String edgesSql,
  required String ownReqSql,
  required String discoverSql,
  required String profilesSql,
  required List<String> nodeIds,
  required List<String> profileIds,
}) async {
  final samples = <double>[];
  final arrayLiteral =
      "ARRAY[${nodeIds.map((id) => "'$id'").join(',')}]::text[]";
  final profileLiteral =
      "ARRAY[${profileIds.map((id) => "'$id'").join(',')}]::text[]";
  final edges = edgesSql.replaceAll('@nodeIds::text[]', arrayLiteral);
  final profiles = profilesSql.replaceAll('@ids::text[]', profileLiteral);

  await conn.execute("SET statement_timeout = '${_probeTimeoutMs}ms'");
  double probeMs;
  bool probeTimedOut = false;
  try {
    final sw = Stopwatch()..start();
    await _runComposed(conn, peerSql, edges, ownReqSql, discoverSql, profiles);
    sw.stop();
    probeMs = sw.elapsedMicroseconds / 1000.0;
  } catch (_) {
    probeTimedOut = true;
    probeMs = _probeTimeoutMs.toDouble();
  }

  if (!probeTimedOut && probeMs <= _slowThresholdMs) {
    samples.add(probeMs);
    for (var i = 0; i < _warmupRuns - 1; i++) {
      await _runComposed(conn, peerSql, edges, ownReqSql, discoverSql, profiles);
    }
    for (var i = 0; i < _timedRuns - 1; i++) {
      final sw = Stopwatch()..start();
      await _runComposed(conn, peerSql, edges, ownReqSql, discoverSql, profiles);
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    }
  } else {
    samples.add(probeMs);
  }
  await conn.execute('SET statement_timeout = 0');
  samples.sort();
  return {
    'p50_ms': _percentile(samples, 0.50),
    'p95_ms': _percentile(samples, 0.95),
    'runs': samples.length,
    if (probeTimedOut)
      'single_sample_reason':
          'exceeded ${_probeTimeoutMs}ms statement_timeout; reported value is the cap'
    else if (probeMs > _slowThresholdMs)
      'single_sample_reason':
          'first sample exceeded ${_slowThresholdMs}ms fast-path threshold; repeated sampling skipped',
    'steps': [
      'person_visible_peers_symmetric',
      'constellation_trust_edges',
      'ownRequests',
      'discoverableRequests',
      'peerProfiles',
    ],
  };
}

Future<void> _runComposed(
  Connection conn,
  String peerSql,
  String edgesSql,
  String ownReqSql,
  String discoverSql,
  String profilesSql,
) async {
  final params = {'viewer': _viewerId};
  await conn.execute(Sql.named(peerSql), parameters: params);
  await conn.execute(Sql.named(edgesSql), parameters: params);
  await conn.execute(Sql.named(ownReqSql), parameters: params);
  await conn.execute(Sql.named(discoverSql), parameters: params);
  await conn.execute(Sql.named(profilesSql), parameters: params);
}
