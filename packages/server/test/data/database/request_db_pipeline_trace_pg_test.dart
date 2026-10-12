@Tags(['pg'])
library;

import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/sentry/sentry_request_context.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/sentry_trace_capture.dart';
import '../../support/transaction_pinned_pool_env.dart';

const _operation = 'ConstellationFull';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DB_REQUEST_TRACE_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_trace',
  );
  final pgUnavailableReason = await pgSkipReason(target);
  final skipReason = pgUnavailableReason ?? false;
  DisposablePgWriterSession? session;
  final capture = SentryTraceCapture();

  group('One HTTP request through the tracing middleware', () {
    setUpAll(() async {
      if (pgUnavailableReason != null) return;
      session = await setUpDisposablePgWriter(target: target);
    });

    tearDownAll(() async {
      if (session case final opened?) {
        await tearDownDisposablePgWriter(session: opened);
      }
    });

    setUp(capture.start);
    tearDown(capture.stop);

    for (final enabled in [false, true]) {
      test(
        'shows admission wait, pool acquire, transaction lifetime and each '
        'SQL statement as distinct spans of the same trace '
        '(${enabled ? 'per-transaction lease' : 'pinned session'})',
        () async {
          final db = TenturaDb(
            transactionPinnedPoolEnv(
              enabled: enabled,
              postgres: target.databaseEnv,
            ),
          );
          addTearDown(db.close);
          final scheduler = ConstellationDbScheduler();
          late int pid;
          final handler = sentryRequestTracing(
            env: Env(sentryDsn: 'https://public@o123.ingest.sentry.io/1'),
          )((request) async {
            SentryRequestContext.from(request)!
                .renameGraphqlOperation(_operation);
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

          final admission = sent.spansWithOperation('db.admission.wait').single;
          final transaction = sent.spansWithOperation('db.transaction').single;
          final acquire = sent.spansWithOperation('db.pool.acquire').single;
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

          expect(
            admission.endsBeforeStartOf(transaction),
            isTrue,
            reason: 'queue time is over before the transaction begins',
          );
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
        skip: skipReason,
      );
    }
  });
}
