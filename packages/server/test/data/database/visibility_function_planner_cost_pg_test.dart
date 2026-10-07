@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _viewerId = 'Ucostplanviewer';
const _peerId = 'Ucostplanpeer01';
const _beaconCount = 600;
const _beaconAnchorCount = 64;
const _visibilityFunctions = [
  'public.beacon_can_read_content(text,text)',
  'public.person_visible_peers_symmetric(text,text)',
  'public.person_visible_peer_ids_tx(text,text)',
  'public.person_are_mutually_visible(text,text,text)',
  'public.person_are_mutually_visible_cached(text,text,text)',
  'public.block_hides(text,text)',
];

// Preserve the historical OR + correlated EXISTS authorization query. Keep
// the scalar visibility call explicit even if production changes its SQL.
const _correlatedAuthorizedAnchorsSql = '''
SELECT ca.person_id, ca.beacon_id, ca.x_units, ca.y_units,
       ca.coordinate_space_version, ca.revision::text AS revision, ca.placed_at
FROM public.constellation_anchor ca
WHERE ca.viewer_id = @viewer
  AND (
    ca.person_id = ANY(@peers::text[])
    OR EXISTS (
      SELECT 1
      FROM public.beacon b
      WHERE b.id = ca.beacon_id
        AND b.published_at IS NOT NULL
        AND public.beacon_can_read_content(b.id, @viewer)
        AND NOT public.block_hides(@viewer, b.user_id)
        AND NOT public.block_hides(b.user_id, @viewer)
    )
  )
ORDER BY ca.placed_at, COALESCE(ca.beacon_id, ca.person_id)
''';

void main() {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VISIBILITY_PLANNER_COST_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_visibility_cost',
  );
  // Keep registration independent of PostgreSQL availability: a fresh SQL
  // file must be wired into the registry before it can price these helpers.
  test('visibility migration declares planner costs for all six helpers', () {
    expect(
      [
        for (final migration in migrationsForTesting)
          if (migration.version.compareTo('0226') > 0 &&
              _declaredCosts(
                migration.statements,
              ).keys.toSet().containsAll(_visibilityFunctions))
            migration.version,
      ],
      isNotEmpty,
      reason:
          'A new registered migration must ALTER FUNCTION ... COST for '
          '${_visibilityFunctions.join(', ')}',
    );
  });

  group('Visibility query plan classification', () {
    test(
      'visibility calls outside a beacon scan filter leave the scan valid',
      () {
        final plan = <String, Object?>{
          'Node Type': 'Result',
          'Filter': "beacon_can_read_content('Bother', 'Uviewer')",
          'Plans': [
            {
              'Node Type': 'Seq Scan',
              'Relation Name': 'beacon',
              'Filter': '(status = 0)',
            },
          ],
        };
        expect(_beaconScanViolations('visibility read', plan), isEmpty);
      },
    );

    test(
      'beacon sequential scans carrying their own visibility filter fail',
      () {
        final plan = <String, Object?>{
          'Node Type': 'Seq Scan',
          'Relation Name': 'beacon',
          'Filter': "beacon_can_read_content(id, 'Uviewer')",
        };
        expect(
          _beaconScanViolations('visibility read', plan),
          contains(contains('Seq Scan on beacon carries')),
        );
      },
    );

    test(
      'hashed subplans without beacon visibility filtering remain valid',
      () {
        final plan = <String, Object?>{
          'Node Type': 'Seq Scan',
          'Relation Name': 'constellation_anchor',
          'Filter': '((hashed SubPlan 1) OR (hashed SubPlan 2))',
          'Output': ["beacon_can_read_content(beacon_id, 'Uviewer')"],
          'Plans': [
            {
              'Node Type': 'Seq Scan',
              'Parent Relationship': 'SubPlan',
              'Subplan Name': 'SubPlan 1',
              'Relation Name': 'user',
              'Filter': "beacon_can_read_content('Bother', id)",
            },
            {
              'Node Type': 'Seq Scan',
              'Parent Relationship': 'SubPlan',
              'Subplan Name': 'SubPlan 2',
              'Relation Name': 'beacon',
              'Filter': '(status = 0)',
            },
          ],
        };
        expect(_beaconScanViolations('visibility read', plan), isEmpty);
      },
    );

    test(
      'hashed user subplans may contain non-hashed beacon visibility probes',
      () {
        final plan = <String, Object?>{
          'Node Type': 'Seq Scan',
          'Relation Name': 'constellation_anchor',
          'Filter': '(hashed SubPlan 1)',
          'Plans': [
            {
              'Node Type': 'Seq Scan',
              'Parent Relationship': 'SubPlan',
              'Subplan Name': 'SubPlan 1',
              'Relation Name': 'user',
              'Filter': '(SubPlan 2)',
              'Plans': [
                {
                  'Node Type': 'Index Scan',
                  'Parent Relationship': 'SubPlan',
                  'Subplan Name': 'SubPlan 2',
                  'Relation Name': 'beacon',
                  'Filter': "beacon_can_read_content(id, 'Uviewer')",
                },
              ],
            },
          ],
        };
        expect(_beaconScanViolations('visibility read', plan), isEmpty);
      },
    );

    test(
      'hashed visibility subplans recognize differing reference formats',
      () {
        for (final reference in [
          '(hashed SubPlan 7)',
          '(ANY (hashed SubPlan 7).col1)',
          '(hashed (SubPlan 7))',
          '(HASHED  SubPlan   7)',
        ]) {
          final plan = <String, Object?>{
            'Node Type': 'Seq Scan',
            'Relation Name': 'constellation_anchor',
            'Filter': reference,
            'Plans': [
              {
                'Node Type': 'Aggregate',
                'Parent Relationship': 'SubPlan',
                'Subplan Name': 'SubPlan 7',
                'Plans': [
                  {
                    'Node Type': 'Index Scan',
                    'Relation Name': 'beacon',
                    'Filter': "beacon_can_read_content(id, 'Uviewer')",
                  },
                ],
              },
            ],
          };
          expect(
            _beaconScanViolations('visibility read', plan),
            contains(contains('hashed SubPlan 7 scans beacon')),
            reason: reference,
          );
        }
      },
    );
  });

  group('Visibility function planner costs', () {
    DisposablePgWriterSession? session;
    TenturaDb? db;
    late _SnapshotQueryPlans plans;

    setUpAll(() async {
      expect(
        await canReachPostgresAdmin(target),
        isTrue,
        reason: 'PostgreSQL is required to check visibility costs and plans',
      );
      final opened = await setUpDisposablePgWriter(target: target);
      session = opened;
      await _seed(opened.writer);
      plans = _SnapshotQueryPlans();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(plans),
      );
    });

    tearDownAll(() async {
      final opened = session;
      if (opened != null) {
        await tearDownDisposablePgWriter(session: opened, drift: db);
      }
    });

    test(
      'registered visibility function costs match explicit migration values',
      () async {
        final actualCosts = <String, double>{};
        for (final signature in _visibilityFunctions) {
          final rows = await session!.writer.execute(
            Sql.named('''
SELECT procost::double precision
FROM pg_catalog.pg_proc
WHERE oid = @signature::regprocedure
'''),
            parameters: {'signature': signature},
          );
          actualCosts[signature] = (rows.single.single! as num).toDouble();
        }

        // Values belong to the measured migration, rather than invented timing
        // thresholds in this test. Inspect the registered statements so an
        // unregistered SQL file cannot satisfy the catalog contract.
        final costMigrations = [
          for (final migration in migrationsForTesting)
            if (migration.version.compareTo('0226') > 0 &&
                _declaredCosts(
                  migration.statements,
                ).keys.toSet().containsAll(_visibilityFunctions))
              migration,
        ];
        expect(
          costMigrations,
          isNotEmpty,
          reason:
              'A migration after the set-based visibility migration must '
              'declare COST for all six visibility functions. '
              'Current pg_proc.procost values: $actualCosts',
        );
        final expectedCosts = _declaredCosts(costMigrations.last.statements);
        for (final signature in _visibilityFunctions) {
          expect(expectedCosts[signature], greaterThan(0), reason: signature);
          expect(
            actualCosts[signature],
            expectedCosts[signature],
            reason:
                '$signature must retain its declared planner cost after '
                'applying the complete migration registry',
          );
        }
      },
    );

    test(
      'authorized anchors and correlated visibility probes avoid full-table '
      'beacon subplans',
      () async {
        final count = await session!.writer.execute(
          "SELECT count(*)::int FROM public.beacon WHERE id LIKE 'Bcostplan%'",
        );
        expect(count.single.single, greaterThanOrEqualTo(500));

        // EXPLAIN every production read with its actual binds, on the same
        // read-only snapshot connection that issues it. This includes anchor
        // authorization without pinning its SQL text or number of statements.
        // Do not force indexes or adjust costs/planner switches in the test.
        plans.snapshotReads.clear();
        final repository = ConstellationFieldRepository(db!, _Profiles());
        await repository.readSnapshot(
          viewerId: _viewerId,
          context: '',
          params: (
            filters: ConstellationFieldMembershipFilters.defaults,
            projection: ConstellationProjection.anchors,
          ),
        );
        expect(
          plans.snapshotReads,
          isNotEmpty,
          reason: 'The anchor projection must issue reads to EXPLAIN',
        );

        // Keep the OR + correlated EXISTS form even when production uses a
        // join: realistic function costs must also protect this query shape.
        final parameters = <String, Object?>{
          'viewer': _viewerId,
          'peers': [_peerId],
        };
        final rows = await session!.writer.execute(
          Sql.named('EXPLAIN (FORMAT JSON) $_correlatedAuthorizedAnchorsSql'),
          parameters: parameters,
        );
        final correlatedPlan = _decodePlan(rows.single.single);

        // Both the count and EXPLAIN use the writer that seeded public.beacon.
        // Execute that exact SQL with the same binds to prove the correlation
        // selects the seeded beacon anchors, rather than an empty candidate set.
        final selected = await session!.writer.execute(
          Sql.named(_correlatedAuthorizedAnchorsSql),
          parameters: parameters,
        );
        expect(
          selected.map((row) => row[1]).whereType<String>().toSet(),
          {
            for (var i = 1; i <= _beaconAnchorCount; i++)
              'Bcostplan${i.toString().padLeft(5, '0')}',
          },
          reason: 'The explained EXISTS query must read the seeded beacon IDs',
        );
        expect(selected.map((row) => row[0]), contains(_peerId));
        expect(
          _planNodes(correlatedPlan).any(
            (node) => node['Relation Name'] == 'beacon',
          ),
          isTrue,
          reason: 'The correlated EXISTS plan must access public.beacon',
        );

        final violations = [
          for (final (index, read) in plans.snapshotReads.indexed)
            ..._beaconScanViolations(
              'production anchor projection read ${index + 1}',
              read.plan,
            ),
          ..._beaconScanViolations(
            'correlated visibility probe',
            correlatedPlan,
          ),
        ];
        expect(
          violations,
          isEmpty,
          reason:
              'Visibility checks must probe the candidate beacon IDs.\n'
              '${violations.join('\n')}\n'
              'Anchor projection reads: ${jsonEncode([
                for (final read in plans.snapshotReads) {'statement': read.statement, 'plan': read.plan},
              ])}'
              '\nCorrelated EXISTS: ${jsonEncode(correlatedPlan)}',
        );
      },
    );
  });
}

Map<String, double> _declaredCosts(Iterable<String> statements) {
  final declarations = RegExp(
    r'ALTER\s+FUNCTION\s+public\.([a-z_]+)\s*\(([^)]*)\)\s+'
    r'COST\s+([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  return {
    for (final statement in statements)
      for (final match in declarations.allMatches(statement))
        'public.${match[1]}('
                '${match[2]!.split(',').map((arg) => arg.trim().split(RegExp(r'\s+')).last).join(',')})':
            double.parse(match[3]!),
  };
}

Map<String, Object?> _decodePlan(Object? value) {
  final decoded = value is String ? jsonDecode(value) : value;
  final document = (decoded! as List).single as Map;
  return Map<String, Object?>.from(document['Plan'] as Map);
}

Iterable<Map<String, Object?>> _planNodes(
  Map<String, Object?> node, {
  bool includeNestedSubplans = true,
}) sync* {
  yield node;
  for (final child in (node['Plans'] as List?) ?? const []) {
    final childNode = Map<String, Object?>.from(child as Map);
    if (!includeNestedSubplans &&
        const [
          'SubPlan',
          'InitPlan',
        ].contains(childNode['Parent Relationship'])) {
      continue;
    }
    yield* _planNodes(childNode, includeNestedSubplans: includeNestedSubplans);
  }
}

List<String> _beaconScanViolations(String label, Map<String, Object?> plan) {
  final violations = <String>[];

  void visit(
    Map<String, Object?> node,
    List<Map<String, Object?>> ancestors,
  ) {
    if (node['Node Type'] == 'Seq Scan' &&
        node['Relation Name'] == 'beacon' &&
        _hasBeaconVisibilityFilter(node)) {
      violations.add(
        '$label: Seq Scan on beacon carries '
        'a beacon_can_read_content filter',
      );
    }
    final subplan = RegExp(
      r'\bSubPlan\s+(\d+)\b',
      caseSensitive: false,
    ).firstMatch(node['Subplan Name'] as String? ?? '');
    if (node['Parent Relationship'] == 'SubPlan' &&
        subplan != null &&
        _planNodes(node, includeNestedSubplans: false).any(
          (child) =>
              child['Relation Name'] == 'beacon' &&
              _hasBeaconVisibilityFilter(child),
        ) &&
        ancestors.any(
          (ancestor) => _referencesHashedSubplan(ancestor, subplan[1]!),
        )) {
      violations.add(
        '$label: hashed ${node['Subplan Name']} scans beacon '
        'with a beacon_can_read_content filter',
      );
    }
    for (final child in (node['Plans'] as List?) ?? const []) {
      visit(Map<String, Object?>.from(child as Map), [...ancestors, node]);
    }
  }

  visit(plan, const []);
  return violations;
}

bool _hasBeaconVisibilityFilter(Map<String, Object?> node) => RegExp(
  r'\bbeacon_can_read_content"?\s*\(',
  caseSensitive: false,
).hasMatch(node['Filter'] as String? ?? '');

bool _referencesHashedSubplan(Map<String, Object?> node, String subplanId) {
  // PostgreSQL renders hash usage in the referencing expression, not as a
  // boolean attribute on the subplan. Match only ancestor expressions, then
  // inspect that named subplan's beacon scan and its own Filter above. This
  // also accepts newer output-column syntax such as (hashed SubPlan 2).col1.
  final reference = RegExp(
    r'\bhashed\s*(?:\(\s*)?SubPlan\s+' + subplanId + r'\b',
    caseSensitive: false,
  );
  for (final field in const [
    'Filter',
    'Join Filter',
    'One-Time Filter',
    'Index Cond',
    'Recheck Cond',
    'Hash Cond',
    'Merge Cond',
    'Output',
  ]) {
    final value = node[field];
    if (value is String && reference.hasMatch(value)) return true;
    if (value is List && value.whereType<String>().any(reference.hasMatch)) {
      return true;
    }
  }
  return false;
}

Future<void> _seed(Connection writer) async {
  for (final (index, id) in [_viewerId, _peerId].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': id,
        'key': pgTestPublicKey('visibility_cost', index + 1),
      },
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable, published_at)
SELECT 'Bcostplan' || lpad(i::text, 5, '0'), @viewer,
       'Planner cost beacon ' || i, '', 0, 0, true, '2026-01-01T00:00:00Z'
FROM generate_series(1, @count::int) AS s(i)
'''),
    parameters: {'viewer': _viewerId, 'count': _beaconCount},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES (@viewer)
'''),
    parameters: {'viewer': _viewerId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, beacon_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
SELECT 'Acostplan' || lpad(i::text, 5, '0'), @viewer,
       'Bcostplan' || lpad(i::text, 5, '0'), 0, 0, 1, i,
       '2026-01-01T00:00:00Z'::timestamptz + i * interval '1 second'
FROM generate_series(1, @count::int) AS s(i)
'''),
    parameters: {'viewer': _viewerId, 'count': _beaconAnchorCount},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES ('Acostplanpeer', @viewer, @peer, 0, 0, 1, 65, '2026-01-02T00:00:00Z')
'''),
    parameters: {'viewer': _viewerId, 'peer': _peerId},
  );
  await writer.execute('ANALYZE public.beacon');
  await writer.execute('ANALYZE public.constellation_anchor');
  await writer.execute('ANALYZE public."user"');
}

final class _SnapshotQueryPlans extends QueryInterceptor {
  final snapshotReads = <({String statement, Map<String, Object?> plan})>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(
      'EXPLAIN (FORMAT JSON) $statement',
      args,
    );
    snapshotReads.add((
      statement: statement,
      plan: _decodePlan(rows.single.values.single),
    ));
    return super.runSelect(executor, statement, args);
  }
}

final class _Profiles implements UserProfileBatchLookup {
  @override
  Future<Map<String, UserEntity>> userEntitiesByIds(
    Iterable<String> ids,
  ) async => {for (final id in ids) id: UserEntity(id: id, displayName: id)};

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
