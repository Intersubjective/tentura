@Tags(['pg'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

// The attention reads (live obligations, the History feed) authorize every
// receipt against its Request. Authorization is a per-Request fact, so its
// cost must grow with the Requests a query looks at, not with the receipts
// stored under them: a busy Request carries many receipts, and checking each
// one separately is what pushed these reads past the statement timeout.
//
// The fixture is a realistic attention history: many receipts per Request,
// few of them live obligations, Requests the viewer reads through every
// route (author, room participant, tombstone of a deleted Request) and
// Requests the viewer cannot read. Ten other accounts carry the same history,
// so, as in production, the viewer's receipts are a small share of the table.
// The tests run the production reads, then replay each SQL statement they
// issued, as issued, to count visibility-function calls and inspect the
// actual plan.
//
// Not covered here: wall-clock timings and the statement timeout itself.
// Those depend on the host and on production data volume; they are measured
// on the perf database and recorded with the change, and the 57014
// classification path is pinned by
// test/app/attention_live_obligations_telemetry_pg_test.dart.

const _viewer = 'Uattentioncost01';
const _other = 'Uattentioncost02';
const _newcomer = 'Uattentioncost03';

/// Accounts with the same history as the viewer on its authored Requests.
final _bystanders = [
  for (var slot = 1; slot <= 9; slot++) 'Uattentioncrowd0$slot',
];

/// Requests the viewer authored.
const _ownRequests = 64;

/// Receipts per Request the viewer authored, for each account.
const _receiptsPerRequest = 16;

/// Authored Requests holding a live obligation for the viewer.
const _liveOwnRequests = 8;

/// Requests by another author the viewer reads as a room participant; each
/// holds one live obligation among [_receiptsPerRequest] receipts.
const _participantRequests = 4;

/// Deleted Requests the viewer offered help on: readable only as tombstones.
const _tombstoneRequests = 4;
const _receiptsPerTombstoneRequest = 4;

/// Unpublished Requests by another author: unreadable. One live obligation
/// among [_receiptsPerHiddenRequest] receipts each.
const _hiddenRequests = 8;
const _receiptsPerHiddenRequest = 4;

const _requestsInHistory =
    _ownRequests + _participantRequests + _tombstoneRequests + _hiddenRequests;
const _requestsWithLiveObligation =
    _liveOwnRequests + _participantRequests + _hiddenRequests;
const _readableLiveObligations = _liveOwnRequests + _participantRequests;
const _viewerReceipts =
    _ownRequests * _receiptsPerRequest +
    _participantRequests * _receiptsPerRequest +
    _tombstoneRequests * _receiptsPerTombstoneRequest +
    _hiddenRequests * _receiptsPerHiddenRequest;
const _readableReceipts =
    _ownRequests * _receiptsPerRequest +
    _participantRequests * _receiptsPerRequest +
    _tombstoneRequests * _receiptsPerTombstoneRequest;

const _visibilityFunctions = [
  'beacon_can_read_content',
  'beacon_can_read_tombstone',
];

const _liveObligationsDocument =
    'query AttentionLiveObligations { liveObligationBeacons }';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_VISIBILITY_COST_TEST_DB',
    defaultNamePrefix: 'tentura_test_attention_visibility_cost',
  );
  final unavailable = await pgSkipReason(target);

  group('attention reads authorize per Request, not per receipt', () {
    late DisposablePgWriterSession session;
    late _StatementCapture capture;
    late TenturaDb database;
    late AttentionRepository repository;
    late Handler graphql;

    setUpAll(() async {
      if (unavailable != null) return;
      session = await setUpDisposablePgWriter(target: target);
      capture = _StatementCapture();
      database = TenturaDb(
        target.databaseEnv,
        scopeInterceptor: () => capture,
      );
      repository = AttentionRepository(database);
      graphql = _graphqlHandler(
        target.databaseEnv,
        QueryAttention(query: repository).liveObligationBeacons,
      );
      await _seed(session.writer);
    });

    tearDownAll(() async {
      if (unavailable != null) return;
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    setUp(() => capture.statements.clear());

    Future<List<String>> liveObligationsOverGraphql(String viewer) =>
        _postLiveObligations(graphql, viewer);

    test(
      'live obligations over GraphQL list only readable Requests and check '
      'visibility at most once per Request holding a live obligation',
      () async {
        // What the client sees: authored and participant Requests with a
        // live obligation; never an unreadable one.
        expect(await liveObligationsOverGraphql(_viewer), [
          for (var i = 0; i < _liveOwnRequests; i++) _ownId(i),
          for (var i = 0; i < _participantRequests; i++) _participantId(i),
        ]);
        final statements = List.of(capture.statements);
        expect(statements, isNotEmpty);

        // A viewer with no attention history gets an empty answer and costs
        // no visibility work at all.
        capture.statements.clear();
        expect(await liveObligationsOverGraphql(_newcomer), isEmpty);
        for (final statement in capture.statements) {
          final calls = await _visibilityCalls(session.writer, statement);
          expect(calls.values.fold(0, (a, b) => a + b), 0);
        }

        for (final statement in statements) {
          await _expectVisibilityCallsAtMost(
            session.writer,
            statement,
            _requestsWithLiveObligation,
            'Requests holding a live obligation',
          );
        }
      },
      skip: unavailable,
    );

    for (final view in [AttentionFeedView.all, AttentionFeedView.needsYou]) {
      test(
        'the ${view.name} attention feed pages through every readable receipt '
        'and checks visibility at most once per Request in each statement',
        () async {
          // Walk every page, as the client does with the cursor.
          final seen = <AttentionReceipt>[];
          AttentionCursor? cursor;
          var pages = 0;
          do {
            final feed = await repository.attentionFeed(
              accountId: _viewer,
              view: view,
              cursor: cursor,
              limit: 100,
            );
            expect(feed.summary.needsYouTotal, _readableLiveObligations);
            seen.addAll(feed.page.items);
            cursor = feed.page.nextCursor;
            pages++;
          } while (cursor != null && pages < 50);

          final ids = seen.map((item) => item.id).toList();
          expect(ids.toSet(), hasLength(ids.length), reason: 'pages overlap');
          final beacons = seen.map((item) => item.beaconId).toSet();
          expect(beacons.where((id) => id!.startsWith('Bcosthid')), isEmpty);
          if (view == AttentionFeedView.needsYou) {
            expect(seen, hasLength(_readableLiveObligations));
          } else {
            expect(seen, hasLength(_readableReceipts));
            final tombstones = seen.where(
              (item) => item.beaconId!.startsWith('Bcosttmb'),
            );
            expect(
              tombstones,
              hasLength(_tombstoneRequests * _receiptsPerTombstoneRequest),
            );
            expect(
              tombstones.map((item) => item.title),
              everyElement(kBeaconUnavailableNotificationTitle),
            );
            expect(
              beacons.where((id) => id!.startsWith('Bcostpart')),
              hasLength(_participantRequests),
            );
          }

          // The cost of the first page and of a page after a cursor.
          capture.statements.clear();
          final first = await repository.attentionFeed(
            accountId: _viewer,
            view: view,
            limit: 4,
          );
          await repository.attentionFeed(
            accountId: _viewer,
            view: view,
            cursor: first.page.nextCursor,
            limit: 4,
          );
          for (final statement in List.of(capture.statements)) {
            await _expectVisibilityCallsAtMost(
              session.writer,
              statement,
              _requestsInHistory,
              "Requests in the viewer's attention history",
            );
          }
        },
        skip: unavailable,
      );
    }

    test(
      'visibility work does not grow when Requests gain more receipts',
      () async {
        Future<int> calls(Future<void> Function() read) async {
          capture.statements.clear();
          await read();
          var total = 0;
          for (final statement in List.of(capture.statements)) {
            final byFunction = await _visibilityCalls(
              session.writer,
              statement,
            );
            total += byFunction.values.fold(0, (a, b) => a + b);
          }
          return total;
        }

        Future<void> live() => repository.liveObligationBeacons(
          accountId: _viewer,
        );
        Future<void> feed() => repository.attentionFeed(
          accountId: _viewer,
          view: AttentionFeedView.all,
          limit: 20,
        );

        final liveBefore = await calls(live);
        final feedBefore = await calls(feed);

        // Twice the optional history on every authored Request, older than
        // anything on the first page, so both answers stay the same.
        addTearDown(
          () => session.writer.execute(
            "DELETE FROM public.notification_outbox WHERE id LIKE 'Ncostmore_%'",
          ),
        );
        await _insertOwnReceipts(
          session.writer,
          idPrefix: 'Ncostmore',
          accounts: const [_viewer],
          withLiveObligations: false,
          olderBy: const Duration(days: 30),
        );

        expect(
          await calls(live),
          liveBefore,
          reason:
              'Live obligations made $liveBefore visibility calls before '
              'the authored Requests doubled their receipts; the count must '
              'depend on Requests, not on receipts.',
        );
        expect(
          await calls(feed),
          feedBefore,
          reason:
              'The feed made $feedBefore visibility calls before the authored '
              'Requests doubled their receipts; the count must depend on '
              'Requests, not on receipts.',
        );
      },
      skip: unavailable,
    );

    test(
      "the live obligations plan reads only the viewer's live obligations "
      'through an account-keyed index and evaluates visibility per Request',
      () async {
        await repository.liveObligationBeacons(accountId: _viewer);
        for (final statement in List.of(capture.statements)) {
          final plan = await _inlinedPlan(session.writer, statement);
          expect(
            _planViolations(
              plan,
              // One pass over the live obligations plus, at most, one key
              // lookup for each of them.
              outboxRowBudget: 2 * _requestsWithLiveObligation,
              requestCap: _requestsWithLiveObligation,
            ),
            isEmpty,
            reason: 'Plan: ${jsonEncode(plan)}',
          );
        }
      },
      skip: unavailable,
    );

    test(
      "the attention feed plan reads the viewer's receipts once through an "
      'account-keyed index and evaluates visibility per Request',
      () async {
        const limit = 20;
        await repository.attentionFeed(
          accountId: _viewer,
          view: AttentionFeedView.all,
          limit: limit,
        );
        for (final statement in List.of(capture.statements)) {
          final plan = await _inlinedPlan(session.writer, statement);
          expect(
            _planViolations(
              plan,
              // The summary counts every receipt of the viewer, so one pass
              // over them is inherent; the page may read its own rows again.
              // A second pass over the whole history, or any other account's
              // rows, is not.
              outboxRowBudget: _viewerReceipts + 2 * (limit + 1),
              requestCap: _requestsInHistory,
            ),
            isEmpty,
            reason: 'Plan: ${jsonEncode(plan)}',
          );
        }
      },
      skip: unavailable,
    );
  });
}

String _ownId(int index) => 'Bcostown${index.toString().padLeft(5, '0')}';
String _participantId(int index) =>
    'Bcostpart${index.toString().padLeft(4, '0')}';

Future<void> _expectVisibilityCallsAtMost(
  pg.Connection writer,
  _Statement statement,
  int ceiling,
  String what,
) async {
  final calls = await _visibilityCalls(writer, statement);
  for (final function in _visibilityFunctions) {
    expect(
      calls[function] ?? 0,
      lessThanOrEqualTo(ceiling),
      reason:
          '$function ran ${calls[function]} times for $ceiling $what (the '
          'viewer has $_viewerReceipts receipts). It must run at most once '
          'per Request, not once per stored receipt. Statement: '
          '${statement.sql}\nPlan: ${jsonEncode(await _inlinedPlan(writer, statement))}',
    );
  }
}

/// Function calls the statement makes, counted inside a rolled-back
/// transaction on the writer connection (`pg_stat_xact_user_functions`).
///
/// The view reads the backend's pending counters, which may still hold calls
/// from earlier transactions that have not been flushed yet, so the count is
/// the difference across the statement.
Future<Map<String, int>> _visibilityCalls(
  pg.Connection writer,
  _Statement statement,
) async {
  Future<Map<String, int>> counters() async {
    final rows = await writer.execute(
      pg.Sql.named('''
SELECT funcname, calls::int
FROM pg_stat_xact_user_functions
WHERE schemaname = 'public' AND funcname = ANY(@names)
'''),
      parameters: {
        'names': pg.TypedValue(pg.Type.textArray, _visibilityFunctions),
      },
    );
    return {for (final row in rows) row[0]! as String: row[1]! as int};
  }

  await writer.execute('BEGIN');
  try {
    await writer.execute("SET LOCAL track_functions = 'all'");
    final before = await counters();
    await writer.execute(statement.sql, parameters: statement.arguments);
    final after = await counters();
    return {
      for (final MapEntry(:key, :value) in after.entries)
        key: value - (before[key] ?? 0),
    };
  } finally {
    await writer.execute('ROLLBACK');
  }
}

/// The actual plan of [statement], with the set-returning SQL functions it
/// scans inlined so their own subqueries and scans are visible.
///
/// PostgreSQL inlines such a function into the calling query unless it
/// carries a `SET` clause (the `search_path` pin). Inside a rolled-back
/// transaction this drops that clause from each scanned function and plans
/// again, until no inlinable function scan is left. PL/pgSQL predicates stay
/// opaque; their per-row cost is what [_visibilityCalls] counts.
Future<Map<String, Object?>> _inlinedPlan(
  pg.Connection writer,
  _Statement statement,
) async {
  await writer.execute('BEGIN');
  try {
    for (var round = 0; ; round++) {
      final plan = await _explain(writer, statement);
      final functions = _nodes(plan)
          .where((n) => n['Node Type'] == 'Function Scan')
          .map((n) => n['Function Name'])
          .whereType<String>()
          .toSet();
      final pinned = functions.isEmpty
          ? const <String>[]
          : (await writer.execute(
              pg.Sql.named('''
SELECT p.oid::regprocedure::text
FROM pg_proc p
JOIN pg_language l ON l.oid = p.prolang
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = ANY(@names)
  AND l.lanname = 'sql' AND p.proretset AND p.proconfig IS NOT NULL
'''),
              parameters: {
                'names': pg.TypedValue(pg.Type.textArray, functions.toList()),
              },
            )).map((row) => row.single! as String).toList();
      if (pinned.isEmpty || round == 5) return plan;
      for (final signature in pinned) {
        await writer.execute('ALTER FUNCTION $signature RESET ALL');
      }
    }
  } finally {
    await writer.execute('ROLLBACK');
  }
}

Future<Map<String, Object?>> _explain(
  pg.Connection writer,
  _Statement statement,
) async {
  final result = await writer.execute(
    'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${statement.sql}',
    parameters: statement.arguments,
  );
  final value = result.single.single;
  final decoded = value is String ? jsonDecode(value) : value;
  return ((decoded! as List<Object?>).single! as Map<String, Object?>)['Plan']!
      as Map<String, Object?>;
}

Iterable<Map<String, Object?>> _nodes(Map<String, Object?> node) sync* {
  yield node;
  for (final child in (node['Plans'] as List<Object?>?) ?? const []) {
    yield* _nodes(child! as Map<String, Object?>);
  }
}

int _rowsOut(Map<String, Object?> node) =>
    (node['Actual Rows']! as num).round() *
    (node['Actual Loops']! as num).round();

/// What is wrong with an actual (inlined) plan for one attention read.
///
/// * Every access to `notification_outbox` goes through an index keyed by the
///   viewer's account (or is a primary-key lookup). A sequential scan, or an
///   index that is not account-keyed, reads other accounts' receipts.
/// * All `notification_outbox` access together returns at most
///   [outboxRowBudget] rows.
/// * A visibility predicate in any node's expressions (a filter, a join
///   condition, a hashed or correlated subquery's scan) is evaluated for at
///   most [requestCap] rows — once per Request, not once per receipt.
/// * No subquery runs more than [requestCap] times.
List<String> _planViolations(
  Map<String, Object?> plan, {
  required int outboxRowBudget,
  required int requestCap,
}) {
  final violations = <String>[];
  var outboxRows = 0;
  for (final node in _nodes(plan)) {
    final type = node['Node Type'];
    final label =
        '$type${node['Relation Name'] == null ? '' : ' on '
                  '${node['Relation Name']}'}${node['Index Name'] == null ? '' : ' '
                  'using ${node['Index Name']}'}';
    if (node['Relation Name'] == 'notification_outbox') {
      outboxRows += _rowsOut(node);
      final keyed = switch (type) {
        'Index Scan' || 'Index Only Scan' =>
          _mentions(node['Index Cond'], 'account_id') ||
              RegExp(r'^\(?\(?id = ').hasMatch(
                (node['Index Cond'] as String?) ?? '',
              ),
        'Bitmap Heap Scan' =>
          _mentions(node['Recheck Cond'], 'account_id') ||
              _nodes(node).any(
                (child) =>
                    child['Node Type'] == 'Bitmap Index Scan' &&
                    _mentions(child['Index Cond'], 'account_id'),
              ),
        _ => false,
      };
      if (!keyed) {
        violations.add(
          '$label reads notification_outbox without an account-keyed index',
        );
      }
    }
    if (_visibilityExpressionFields.any(
      (field) => _visibilityCall.hasMatch((node[field] as String?) ?? ''),
    )) {
      final evaluated =
          ((node['Actual Rows']! as num) +
                  ((node['Rows Removed by Filter'] as num?) ?? 0) +
                  ((node['Rows Removed by Join Filter'] as num?) ?? 0))
              .round() *
          (node['Actual Loops']! as num).round();
      if (evaluated > requestCap) {
        violations.add(
          '$label evaluates a visibility predicate for $evaluated rows; '
          'at most $requestCap Requests are involved',
        );
      }
    }
    if (node['Parent Relationship'] == 'SubPlan' &&
        (node['Actual Loops']! as num) > requestCap) {
      violations.add(
        '${node['Subplan Name']} ($label) runs ${node['Actual Loops']} '
        'times; at most $requestCap Requests are involved',
      );
    }
  }
  if (outboxRows > outboxRowBudget) {
    violations.add(
      'notification_outbox access returns $outboxRows rows; the budget is '
      '$outboxRowBudget (the viewer has $_viewerReceipts receipts, ten other '
      'accounts as many each)',
    );
  }
  return violations;
}

const _visibilityExpressionFields = [
  'Filter',
  'Join Filter',
  'Hash Cond',
  'Merge Cond',
  'Index Cond',
  'Recheck Cond',
  'One-Time Filter',
];

final _visibilityCall = RegExp(
  r'\bbeacon_can_read_(?:content|tombstone)"?\s*\(',
  caseSensitive: false,
);

bool _mentions(Object? expression, String column) =>
    expression is String && RegExp('\\b$column\\b').hasMatch(expression);

Handler _graphqlHandler(Env base, GraphQLObjectField<dynamic, dynamic> field) {
  final env = Env(
    environment: Environment.test,
    printEnv: false,
    isDebugModeOn: false,
    pgHost: base.pgHost,
    pgPort: base.pgPort,
    pgDatabase: base.pgDatabase,
    pgUsername: base.pgUsername,
    pgPassword: base.pgPassword,
  );
  final controller = GraphqlController(
    env,
    schema: TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')..fields.add(field),
      ),
    ),
  );
  return requestContextIoAdapter(controller.handler);
}

/// The production `AttentionLiveObligations` operation, as [viewer].
Future<List<String>> _postLiveObligations(
  Handler handler,
  String viewer,
) async {
  final response = await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v2/graphql'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'query': _liveObligationsDocument,
        'operationName': 'AttentionLiveObligations',
      }),
      context: {kContextJwtKey: JwtEntity(sub: viewer)},
    ),
  );
  expect(response.statusCode, 200);
  final body =
      jsonDecode(await response.readAsString()) as Map<String, Object?>;
  expect(body['errors'], isNull);
  final data = body['data']! as Map<String, Object?>;
  return (data['liveObligationBeacons']! as List<Object?>).cast<String>();
}

Future<void> _seed(pg.Connection writer) async {
  for (final (index, id) in [_viewer, _other, _newcomer].indexed) {
    await writer.execute(
      pg.Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {
        'id': id,
        'key': pgTestPublicKey('attentioncost', index + 1),
      },
    );
  }
  for (final (index, id) in _bystanders.indexed) {
    await writer.execute(
      pg.Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': pgTestPublicKey('crowd', index + 1)},
    );
  }
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status)
    SELECT 'Bcostown' || lpad(n::text, 5, '0'), '$_viewer',
           'Own request', 'Visibility cost fixture', 0
    FROM generate_series(0, ${_ownRequests - 1}) n
  ''');
  // Published but not discoverable: the viewer reads these only because
  // they are a room participant.
  await writer.execute('''
    INSERT INTO public.beacon (
      id, user_id, title, description, status, published_at, is_discoverable
    )
    SELECT 'Bcostpart' || lpad(n::text, 4, '0'), '$_other',
           'Participant request', 'Visibility cost fixture', 0, now(), false
    FROM generate_series(0, ${_participantRequests - 1}) n
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_participant (beacon_id, user_id, role)
    SELECT 'Bcostpart' || lpad(n::text, 4, '0'), '$_viewer', 1
    FROM generate_series(0, ${_participantRequests - 1}) n
  ''');
  // Deleted (status 2) Requests the viewer offered help on: no content, but
  // their tombstone stays readable.
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status)
    SELECT 'Bcosttmb' || lpad(n::text, 5, '0'), '$_other',
           'Deleted request', 'Visibility cost fixture', 2
    FROM generate_series(0, ${_tombstoneRequests - 1}) n
  ''');
  await writer.execute('''
    INSERT INTO public.beacon_help_offer (beacon_id, user_id)
    SELECT 'Bcosttmb' || lpad(n::text, 5, '0'), '$_viewer'
    FROM generate_series(0, ${_tombstoneRequests - 1}) n
  ''');
  // Unpublished and authored by someone else: no branch of the content or
  // tombstone predicate lets the viewer read these.
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status)
    SELECT 'Bcosthid' || lpad(n::text, 5, '0'), '$_other',
           'Hidden request', 'Visibility cost fixture', 0
    FROM generate_series(0, ${_hiddenRequests - 1}) n
  ''');

  await _insertOwnReceipts(
    writer,
    idPrefix: 'Ncost',
    accounts: [_viewer, _other, ..._bystanders],
    withLiveObligations: true,
    olderBy: Duration.zero,
  );
  await _insertReceipts(
    writer,
    idPrefix: 'Ncostpart',
    beaconPrefix: 'Bcostpart',
    pad: 4,
    requests: _participantRequests,
    perRequest: _receiptsPerRequest,
    accessPolicy: 'beacon_content',
    liveFirst: true,
    olderBy: const Duration(hours: 20),
  );
  await _insertReceipts(
    writer,
    idPrefix: 'Ncosttmb',
    beaconPrefix: 'Bcosttmb',
    pad: 5,
    requests: _tombstoneRequests,
    perRequest: _receiptsPerTombstoneRequest,
    accessPolicy: 'beacon_tombstone',
    liveFirst: false,
    olderBy: const Duration(hours: 22),
  );
  await _insertReceipts(
    writer,
    idPrefix: 'Ncosthid',
    beaconPrefix: 'Bcosthid',
    pad: 5,
    requests: _hiddenRequests,
    perRequest: _receiptsPerHiddenRequest,
    accessPolicy: 'beacon_content',
    liveFirst: true,
    olderBy: const Duration(days: 1),
  );
  await writer.execute('ANALYZE public.notification_outbox');
  await writer.execute('ANALYZE public.beacon');
}

/// [_receiptsPerRequest] receipts per authored Request for each of
/// [accounts]; with [withLiveObligations], receipt 0 of the first
/// [_liveOwnRequests] Requests is a live obligation.
Future<void> _insertOwnReceipts(
  pg.Connection writer, {
  required String idPrefix,
  required List<String> accounts,
  required bool withLiveObligations,
  required Duration olderBy,
}) => writer.execute('''
    INSERT INTO public.notification_outbox (
      id, account_id, category, kind, priority, title, body, action_url,
      dedup_key, beacon_id, source_event_key, destination_kind,
      presentation_key, presentation_payload, suppression_class, access_policy,
      requires_action, attention_thread_key, created_at
    )
    SELECT '${idPrefix}_' || a.account_id || '_' || r || '_' || e,
           a.account_id,
           'asksOfMe',
           CASE WHEN live THEN 'needsMe' ELSE 'roomMessage' END,
           'normal', 'Fixture', 'Fixture', '/attention',
           '$idPrefix-' || a.account_id || '_' || r || '_' || e,
           'Bcostown' || lpad(r::text, 5, '0'),
           '$idPrefix-source-' || a.account_id || '_' || r || '_' || e,
           'beacon', 'request_status_changed',
           '{"eventType":"fixture"}'::jsonb, 'standard', 'beacon_content',
           live,
           CASE WHEN live
             THEN 'v1|needsMe|' || r || '_' || e || '|' || a.account_id
           END,
           now() - make_interval(secs => ${olderBy.inSeconds})
             - make_interval(mins => r * $_receiptsPerRequest + e)
    FROM unnest(ARRAY[${accounts.map((a) => "'$a'").join(', ')}]) a(account_id)
    CROSS JOIN generate_series(0, ${_ownRequests - 1}) r
    CROSS JOIN generate_series(0, ${_receiptsPerRequest - 1}) e
    CROSS JOIN LATERAL (
      SELECT $withLiveObligations AND e = 0 AND r < $_liveOwnRequests AS live
    ) obligation
  ''');

/// The viewer's receipts on Requests named [beaconPrefix] + index; with
/// [liveFirst], receipt 0 of each is a live obligation.
Future<void> _insertReceipts(
  pg.Connection writer, {
  required String idPrefix,
  required String beaconPrefix,
  required int pad,
  required int requests,
  required int perRequest,
  required String accessPolicy,
  required bool liveFirst,
  required Duration olderBy,
}) => writer.execute('''
    INSERT INTO public.notification_outbox (
      id, account_id, category, kind, priority, title, body, action_url,
      dedup_key, beacon_id, source_event_key, destination_kind,
      presentation_key, presentation_payload, suppression_class, access_policy,
      requires_action, attention_thread_key, created_at
    )
    SELECT '${idPrefix}_' || r || '_' || e,
           '$_viewer',
           'asksOfMe',
           CASE WHEN live THEN 'needsMe' ELSE 'roomMessage' END,
           'normal', 'Fixture', 'Fixture', '/attention',
           '$idPrefix-' || r || '_' || e,
           '$beaconPrefix' || lpad(r::text, $pad, '0'),
           '$idPrefix-source-' || r || '_' || e,
           'beacon', 'request_status_changed',
           '{"eventType":"fixture"}'::jsonb, 'standard', '$accessPolicy',
           live,
           CASE WHEN live THEN 'v1|needsMe|$idPrefix' || r || '|$_viewer' END,
           now() - make_interval(secs => ${olderBy.inSeconds})
             - make_interval(mins => r * 10 + e)
    FROM generate_series(0, ${requests - 1}) r
    CROSS JOIN generate_series(0, ${perRequest - 1}) e
    CROSS JOIN LATERAL (SELECT $liveFirst AND e = 0 AS live) obligation
  ''');

final class _Statement {
  _Statement(this.sql, this.arguments);
  final String sql;
  final List<Object?> arguments;
}

/// Records every SELECT the repository sends, so the test can replay the
/// production statements as issued.
final class _StatementCapture extends QueryInterceptor {
  final statements = <_Statement>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(_Statement(statement, List.of(args)));
    return executor.runSelect(statement, args);
  }
}
