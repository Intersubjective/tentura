@Tags(['pg', 'multi-connection'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/sentry/sentry_request_context.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/sentry_trace_capture.dart';

const _operation = 'ConstellationFull';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DB_REQUEST_TRACE_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_trace',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }
  late DisposablePgWriterSession session;
  final capture = SentryTraceCapture();

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));
  setUp(capture.start);
  tearDown(capture.stop);

  group('One HTTP request through the tracing middleware on a scoped pool', () {
    test(
      'shows admission wait, pool acquire, transaction lifetime and each SQL '
      'statement as distinct spans of the same trace',
      () async {
        final dbEnv = target.databaseEnv;
        final pool = MainDbPool(
          Env(
            environment: Environment.test,
            printEnv: false,
            isDebugModeOn: false,
            pgHost: dbEnv.pgHost,
            pgPort: dbEnv.pgPort,
            pgDatabase: dbEnv.pgDatabase,
            pgUsername: dbEnv.pgUsername,
            pgPassword: dbEnv.pgPassword,
            maxConnectionCount: 2,
          ),
        );
        addTearDown(pool.close);
        final db = TenturaDb.scoped(pool);
        addTearDown(db.close);
        final scheduler = ConstellationDbScheduler();
        late int pid;
        final handler =
            sentryRequestTracing(
              env: Env(sentryDsn: 'https://public@o123.ingest.sentry.io/1'),
            )((request) async {
              SentryRequestContext.from(
                request,
              )!.renameGraphqlOperation(_operation);
              pid = await scheduler.run(
                ConstellationDbWorkKind.full,
                () => db.transaction(() async {
                  final row = await db
                      .customSelect('SELECT pg_backend_pid() AS pid')
                      .getSingle();
                  await db.customSelect('SELECT 2 AS second_statement').get();
                  return row.read<int>('pid');
                }),
              );
              return Response.ok('ok');
            });

        final response = await handler(
          Request('POST', Uri.parse('http://localhost/api/v2/graphql')),
        );

        expect(response.statusCode, 200);
        final sent = capture.sent;
        final root = sent.contexts.trace!;
        expect(sent.spans, isNotEmpty);
        expect(
          sent.spans.map((s) => s.context.traceId),
          everyElement(root.traceId),
        );
        expect(sent.spans.every((s) => s.finished), isTrue);

        final admission = sent
            .spansWithOperation('db.admission.wait')
            .singleWhere((s) => s.tags['work.class'] == 'full');
        final transaction = sent.spansWithOperation('db.transaction').single;
        final acquire = sent
            .spansWithOperation('db.pool.acquire')
            .singleWhere(
              (s) => s.context.parentSpanId == transaction.context.spanId,
            );
        final statements = sent
            .spansWithOperation('db.sql')
            .where((s) => s.context.parentSpanId == transaction.context.spanId)
            .toList();

        expect(admission.context.parentSpanId, root.spanId);
        expect(transaction.context.parentSpanId, root.spanId);
        expect(acquire.context.parentSpanId, transaction.context.spanId);
        expect(
          statements.map((s) => s.context.description ?? ''),
          containsAll([
            contains('pg_backend_pid'),
            contains('second_statement'),
          ]),
        );
        expect(admission.endsBeforeStartOf(transaction), isTrue);
        expect(acquire.isWithin(transaction), isTrue);
        for (final statement in statements) {
          expect(acquire.endsBeforeStartOf(statement), isTrue);
          expect(statement.isWithin(transaction), isTrue);
        }
        expect(admission.tags['graphql.operation'], _operation);
        expect(admission.tags['work.class'], 'full');
        expect(transaction.tags['graphql.operation'], _operation);
        expect(transaction.tags['db.backend_pid'], '$pid');
      },
    );
  });
}
