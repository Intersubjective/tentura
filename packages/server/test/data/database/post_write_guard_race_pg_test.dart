@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_wait.dart';
import '../../support/post_write_guard_fixture.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_WRITE_GUARD_RACE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_write_race',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('Post close serializes with authored database writes', () {
    late DisposablePgWriterSession session;
    late TenturaDb closerDb;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      closerDb = openDisposablePgDatabase(target);
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
    });
    setUp(() => seedPostWriteGuard(session.writer));
    tearDownAll(() async {
      await writer.close();
      await tearDownDisposablePgWriter(session: session, drift: closerDb);
    });

    // Exercise both lock strengths: message/reaction use NO KEY UPDATE, and
    // attachment uses KEY SHARE despite lacking a direct FK to beacon.
    for (final probe in postWriteProbes.take(3)) {
      test('${probe.table} waits for an uncommitted close and then refuses '
          'the write with post_archived without leaving a row', () async {
        final pid =
            (await writer.execute('SELECT pg_backend_pid()')).single.single!
                as int;
        final closeHeld = Completer<void>();
        final releaseClose = Completer<void>();
        final close = MutatingUnitOfWork(closerDb).run(
          actorUserId: guardAuthor,
          action: () async {
            await PostLockRepository(closerDb).lockForPostMutation(guardPost);
            await closerDb.customStatement(
              "UPDATE public.beacon SET status = 6 WHERE id = '$guardPost'",
            );
            closeHeld.complete();
            await releaseClose.future;
          },
        );
        // Also propagate setup errors immediately instead of waiting forever
        // for a signal the closer would then never send.
        final closeObserved = close.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace stack) {
            if (!closeHeld.isCompleted) closeHeld.completeError(error, stack);
            return error;
          },
        );
        Object? outcome;
        var finished = false;
        Future<void>? attempt;
        var blocked = false;
        try {
          await closeHeld.future.timeout(kCompletionWait);
          attempt = writer
              .execute(probe.insert)
              .then<void>(
                (_) {
                  finished = true;
                },
                onError: (Object error) {
                  outcome = error;
                  finished = true;
                },
              );
          final budget = Stopwatch()..start();
          while (!finished && budget.elapsed < kStableStateWait) {
            final activity = await session.writer.execute(
              Sql.named('''
SELECT wait_event_type = 'Lock'
FROM pg_stat_activity
WHERE datname = current_database() AND pid = @pid AND state = 'active'
'''),
              parameters: {'pid': pid},
            );
            if (activity.isNotEmpty && activity.single.single == true) {
              blocked = true;
              break;
            }
          }
        } finally {
          // Always release A before checking assertions: a red test must not
          // leave B or the production transaction hanging until a timeout.
          releaseClose.complete();
          final closeError = await closeObserved.timeout(kCompletionWait);
          expect(closeError, isNull, reason: 'the close transaction commits');
          await attempt?.timeout(kCompletionWait);
        }
        expect(
          blocked,
          isTrue,
          reason: '${probe.table} must wait on the closer beacon row lock',
        );
        expect(outcome, postArchived);
        expect(await session.writer.execute(probe.read), isEmpty);
        expect(
          (await session.writer.execute(
            'SELECT status::int FROM public.beacon '
            "WHERE id = '$guardPost'",
          )).single.single,
          6,
        );
      });
    }
  });
}
