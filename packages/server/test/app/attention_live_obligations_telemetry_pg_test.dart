@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/query/query_attention.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/request_context.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';
import '../support/pg_wait.dart';

const _viewer = 'Uattentiontiming01';
const _other = 'Uattentiontiming02';
const _beaconCount = 128;
const _receiptsPerBeacon = 16;
const _document = 'query AttentionLiveObligations { liveObligationBeacons }';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_TELEMETRY_TEST_DB',
    defaultNamePrefix: 'tentura_test_attention_telemetry',
  );
  final unavailable = await pgSkipReason(target);

  test(
    'seeded live obligations stay within the statement budget and a '
    'disconnected PostgreSQL query produces no Sentry error',
    () async {
      // The timeout control below uses a separate physical pool, so there is
      // no shared executor between the two database instances.
      final warnAboutMultipleDatabases =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            warnAboutMultipleDatabases;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      final env = _databaseEnv(target.databaseEnv);
      final pool = MainDbPool(env);
      addTearDown(pool.close);
      final capture = _QueryMeasurements();
      final database = TenturaDb.scoped(pool, scopeInterceptor: () => capture);
      addTearDown(database.close);
      await _seed(session.writer);

      final events = <SentryEvent>[];
      await Sentry.close();
      await Sentry.init((options) {
        options
          ..dsn = env.sentryDsn
          // Surface failures in test callbacks rather than swallowing them.
          // ignore: invalid_use_of_internal_member
          ..automatedTestMode = true
          ..tracesSampleRate = 1.0
          ..beforeSend = (event, hint) {
            final filtered = scrubAndFilterSentryEvent(event, hint);
            if (filtered != null) events.add(filtered);
            return null;
          }
          ..beforeSendTransaction = (transaction, hint) => null;
      });
      addTearDown(Sentry.close);

      // Use the production GraphQL field and repository, with real rows and
      // authorization. The small schema only avoids unrelated DI bindings.
      final controller = _controller(
        env,
        QueryAttention(
          query: AttentionRepository(database),
        ).liveObligationBeacons,
      );
      final traced = sentryRequestTracing(env: env)((request) async {
        return controller.handler(
          request.change(
            context: {kContextJwtKey: const JwtEntity(sub: _viewer)},
          ),
        );
      });
      final handler = requestContextIoAdapter(traced);
      final expected = List.generate(_beaconCount, _beaconId)..sort();

      // Record a first read and three concurrent reads of the same seeded
      // viewer. All rows must reach the caller; an empty stub cannot pass.
      final first = await _post(handler, _document, 'AttentionLiveObligations');
      final firstSample = capture.samples.single;
      // Include the executed SQL and seeded parameters with the measurement.
      print('Measured SQL: ${firstSample.sql}; args: ${firstSample.arguments}');
      final plan = await session.writer.execute(
        'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${firstSample.sql}',
        parameters: firstSample.arguments,
      );
      // Keep the actual plan in test output, including rows, loops and buffers,
      // so a slow sample can be investigated without silently raising timeouts.
      print(
        'AttentionLiveObligations EXPLAIN: ${jsonEncode(plan.single.single)}',
      );

      final concurrent = await Future.wait(
        List.generate(
          3,
          (_) async => _post(handler, _document, 'AttentionLiveObligations'),
        ),
      );
      expect(capture.samples, hasLength(4));
      final request = RequestContext(requestId: 'measurement-budget');
      final effectiveBudgetMs = min(
        env.pgStatementTimeoutMs,
        request.remaining.inMilliseconds,
      );
      request.dispose();
      final slowestQueryMs = capture.samples
          .map((sample) => sample.elapsed.inMicroseconds / 1000)
          .reduce(max);
      // Emit the measured workload and its unchanged production time budgets.
      print(
        jsonEncode({
          'operation': 'AttentionLiveObligations',
          'viewerBeacons': _beaconCount,
          'viewerReceipts': _beaconCount * _receiptsPerBeacon,
          'otherViewerReceipts': _beaconCount * _receiptsPerBeacon,
          'concurrentReaders': 3,
          'statementTimeoutMs': env.pgStatementTimeoutMs,
          'effectiveRequestBudgetMs': effectiveBudgetMs,
          'postgresStatementDeadlineComparison': {
            'configuredDeadlineMs': env.pgStatementTimeoutMs,
            'slowestQueryMs': slowestQueryMs,
            'exceedsDeadline': slowestQueryMs >= env.pgStatementTimeoutMs,
            'marginMs': env.pgStatementTimeoutMs - slowestQueryMs,
            'conclusion': slowestQueryMs >= env.pgStatementTimeoutMs
                ? 'Seeded query exceeds the PostgreSQL statement deadline; '
                      'EXPLAIN-backed query optimization is required.'
                : 'Seeded query stays below the PostgreSQL statement deadline '
                      'for this workload; production tail latency is unmeasured.',
            'ifExceeded':
                'Optimize using the emitted EXPLAIN plan; do not '
                'silence the timeout or increase its deadline.',
          },
          'sqlElapsedMs': capture.samples
              .map((sample) => sample.elapsed.inMicroseconds / 1000)
              .toList(),
        }),
      );
      for (final sample in capture.samples) {
        expect(
          sample.elapsed,
          lessThan(Duration(milliseconds: env.pgStatementTimeoutMs)),
          reason:
              'The query must finish before the configured PostgreSQL '
              'statement deadline. A violation requires EXPLAIN-backed query '
              'optimization, not a timeout increase or telemetry suppression.',
        );
        expect(sample.error, isNull);
        expect(
          sample.elapsed.inMilliseconds,
          lessThan(effectiveBudgetMs),
          reason:
              'If this fails, inspect the emitted EXPLAIN before optimizing; '
              'do not hide the failure by increasing the deadline.',
        );
      }
      expect(first['data'], {'liveObligationBeacons': expected});
      for (final response in concurrent) {
        expect(response['data'], {'liveObligationBeacons': expected});
      }
      expect(events, isEmpty);

      // Genuine statement timeout control: PostgreSQL, not this test, creates
      // the 57014. The HTTP request is still connected and within its budget.
      final timedDatabase = TenturaDb(
        _databaseEnv(target.databaseEnv, statementTimeoutMs: 100),
      );
      addTearDown(timedDatabase.close);
      final timeoutController = _controller(
        env,
        GraphQLObjectField<String, Object?>(
          'slowStatement',
          graphQLString,
          resolve: (_, _) async {
            await timedDatabase.customSelect('SELECT pg_sleep(1)').get();
            return 'completed';
          },
        ),
      );
      final timeoutResponse = await _post(
        requestContextIoAdapter(
          sentryRequestTracing(env: env)(timeoutController.handler),
        ),
        'query StatementTimeout { slowStatement }',
        'StatementTimeout',
      );
      expect(timeoutResponse['errors'], isNotEmpty);
      expect(events, hasLength(1));
      expect(
        events.single.throwable,
        isA<pg.ServerException>().having(
          (error) => error.code,
          'SQLSTATE',
          '57014',
        ),
      );
      events.clear();

      // Hold only this disposable database's receipt table. The real repository
      // SELECT reaches PostgreSQL and waits on it before the TCP peer closes.
      final finished = Completer<void>();
      RequestContext? disconnectedContext;
      final listening = Completer<({Object address, int port})>();
      final server = await shelfRun(
        () => requestContextIoAdapter((request) async {
          disconnectedContext = RequestContext.current;
          try {
            return await traced(request);
          } finally {
            finished.complete();
          }
        }),
        defaultBindAddress: InternetAddress.loopbackIPv4,
        defaultBindPort: 0,
        defaultEnableHotReload: false,
        onStarted: (address, port) =>
            listening.complete((address: address, port: port)),
      );
      addTearDown(server.close);
      final endpoint = await listening.future;
      final socket = await Socket.connect(endpoint.address, endpoint.port);
      addTearDown(socket.destroy);
      await session.writer.execute('BEGIN');
      try {
        await session.writer.execute(
          'LOCK TABLE public.notification_outbox IN ACCESS EXCLUSIVE MODE',
        );
        final body = utf8.encode(
          jsonEncode({
            'operationName': 'AttentionLiveObligations',
            'query': _document,
          }),
        );
        socket
          ..write(
            'POST /api/v2/graphql HTTP/1.1\r\n'
            'Host: localhost\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: ${body.length}\r\n\r\n',
          )
          ..add(body);
        await socket.flush();
        await _waitForBlockedQuery(session.writer, finished.future);
        expect(disconnectedContext?.isCancelled, isFalse);
        socket.destroy();
        await finished.future.timeout(kCompletionWait);
      } finally {
        socket.destroy();
        await session.writer.execute('ROLLBACK');
      }

      expect(disconnectedContext?.isCancelled, isTrue);
      final cancelled = capture.samples.last;
      expect(
        cancelled.error,
        isA<pg.ServerException>()
            .having((error) => error.code, 'SQLSTATE', '57014')
            .having(
              (error) => error.message,
              'cancel origin',
              contains('user request'),
            ),
        reason:
            'A real driver cancellation must arrive before any telemetry assertion.',
      );
      expect(pool.admission.running, 0);
      expect(pool.admission.queued, 0);
      final recovered = await _post(
        handler,
        _document,
        'AttentionLiveObligations',
      );
      expect(recovered['data'], {'liveObligationBeacons': expected});
      expect(
        events,
        isEmpty,
        reason:
            'A disconnected AttentionLiveObligations query must not create a Sentry error.',
      );
    },
    skip: unavailable,
  );
}

Env _databaseEnv(Env base, {int? statementTimeoutMs}) => Env(
  environment: Environment.test,
  printEnv: false,
  isDebugModeOn: false,
  pgHost: base.pgHost,
  pgPort: base.pgPort,
  pgDatabase: base.pgDatabase,
  pgUsername: base.pgUsername,
  pgPassword: base.pgPassword,
  pgStatementTimeoutMs: statementTimeoutMs ?? base.pgStatementTimeoutMs,
  sentryDsn: 'https://public@o123.ingest.sentry.io/1',
);

GraphqlController _controller(
  Env env,
  GraphQLObjectField<dynamic, dynamic> field,
) => GraphqlController(
  env,
  schema: TenturaGraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', 'Query root')..fields.add(field),
    ),
  ),
);

Future<Map<String, dynamic>> _post(
  Handler handler,
  String document,
  String operation,
) async {
  final response = await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v2/graphql'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'query': document, 'operationName': operation}),
    ),
  );
  expect(response.statusCode, 200);
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

String _beaconId(int index) => 'Battention${index.toString().padLeft(5, '0')}';

Future<void> _seed(pg.Connection writer) async {
  for (final (index, id) in [_viewer, _other].indexed) {
    await writer.execute(
      pg.Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) VALUES (@id, @id, @key)',
      ),
      parameters: {
        'id': id,
        'key': pgTestPublicKey('attentiontiming', index + 1),
      },
    );
  }
  await writer.execute('''
    INSERT INTO public.beacon (id, user_id, title, description, status)
    SELECT 'Battention' || lpad(n::text, 5, '0'), '$_viewer',
           'Seeded request', 'Timing fixture', 0
    FROM generate_series(0, ${_beaconCount - 1}) n
  ''');
  await writer.execute('''
    INSERT INTO public.notification_outbox (
      id, account_id, category, kind, priority, title, body, action_url,
      dedup_key, beacon_id, source_event_key, destination_kind,
      presentation_key, presentation_payload, suppression_class, access_policy,
      requires_action, attention_thread_key
    )
    SELECT 'Nattention' || n || '_' || a,
           CASE a WHEN 1 THEN '$_viewer' ELSE '$_other' END,
           'asksOfMe', 'needsMe', 'normal', 'Obligation', 'Fixture', '/attention',
           'dedup-' || n || '_' || a,
           'Battention' || lpad((n % $_beaconCount)::text, 5, '0'),
           'source-' || n || '_' || a, 'beacon', 'request_status_changed',
           '{"eventType":"fixture"}'::jsonb, 'standard', 'beacon_content',
           true, 'v1|needsMe|' || n || '_' || a || '|' ||
             CASE a WHEN 1 THEN '$_viewer' ELSE '$_other' END
    FROM generate_series(0, ${_beaconCount * _receiptsPerBeacon - 1}) n
    CROSS JOIN generate_series(1, 2) a
  ''');
  await writer.execute('ANALYZE public.notification_outbox');
  await writer.execute('ANALYZE public.beacon');
}

Future<void> _waitForBlockedQuery(
  pg.Connection writer,
  Future<void> finished,
) async {
  final clock = Stopwatch()..start();
  var handled = false;
  unawaited(finished.then((_) => handled = true));
  while (clock.elapsed < kStableStateWait) {
    await writer.execute('SELECT pg_stat_clear_snapshot()');
    final rows = await writer.execute('''
      SELECT pid FROM pg_stat_activity
      WHERE datname = current_database() AND pid <> pg_backend_pid()
        AND state = 'active' AND wait_event_type = 'Lock'
        AND query LIKE '%visible_attention_receipts%'
    ''');
    if (rows.isNotEmpty) return;
    if (handled) {
      fail('The request completed before its query reached the database lock.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('The production live-obligations query never reached PostgreSQL.');
}

final class _QuerySample {
  _QuerySample(this.sql, this.arguments, this.elapsed, this.error);
  final String sql;
  final List<Object?> arguments;
  final Duration elapsed;
  final Object? error;
}

final class _QueryMeasurements extends QueryInterceptor {
  final samples = <_QuerySample>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (!statement.contains('visible_attention_receipts')) {
      return executor.runSelect(statement, args);
    }
    final clock = Stopwatch()..start();
    Object? error;
    try {
      return await executor.runSelect(statement, args);
    } on Object catch (failure) {
      error = failure;
      rethrow;
    } finally {
      samples.add(_QuerySample(statement, List.of(args), clock.elapsed, error));
    }
  }
}
