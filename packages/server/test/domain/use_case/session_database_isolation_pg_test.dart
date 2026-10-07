@Tags(['pg'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/use_case/session_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _accountId = 'Uauthisolation01';
const _latencyBudget = Duration(milliseconds: 500);

/// Start the competing operation after BEGIN has acquired the main database
/// connection and the five-second query has been submitted on that connection.
/// A completer avoids relying on a delay or a transient pg_stat_activity row.
Future<({T value, Duration elapsed})> _duringMainDatabaseSleep<T>(
  TenturaDb mainDatabase,
  Future<T> Function() operation,
) async {
  final sleepSubmitted = Completer<void>();
  final blocker = mainDatabase.transaction(() async {
    final sleep = mainDatabase.customStatement('SELECT pg_sleep(5)');
    sleepSubmitted.complete();
    await sleep;
  });

  try {
    // Also propagate transaction startup failures instead of waiting forever
    // for a barrier that a failed BEGIN could never reach.
    await Future.any<void>([
      sleepSubmitted.future,
      blocker,
    ]).timeout(kCompletionWait);
    expect(sleepSubmitted.isCompleted, isTrue);

    final stopwatch = Stopwatch()..start();
    final value = await operation().timeout(kCompletionWait);
    stopwatch.stop();
    return (value: value, elapsed: stopwatch.elapsed);
  } finally {
    // Drain the blocker before database teardown, including on a red assertion.
    await blocker.timeout(kCompletionWait);
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SESSION_DATABASE_ISOLATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_session_isolation',
  );
  final skipReason = await pgSkipReason(target);

  group(
    'Session traffic while the main database connection is occupied',
    () {
      DisposablePgWriterSession? session;
      TenturaDb? mainDatabase;
      TenturaDb? authDatabase;
      late SessionCase sessionCase;
      late String token;

      setUpAll(() async {
        if (skipReason != null) return;

        session = await setUpDisposablePgWriter(target: target);
        final databaseEnv = target.databaseEnv;
        final env = Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicOrigin: 'http://127.0.0.1:2080',
          pgHost: databaseEnv.pgHost,
          pgPort: databaseEnv.pgPort,
          pgDatabase: databaseEnv.pgDatabase,
          pgUsername: databaseEnv.pgUsername,
          pgPassword: databaseEnv.pgPassword,
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          printEnv: false,
          isDebugModeOn: true,
          workersCount: 1,
        );
        // Exercise the generated application graph, rather than constructing a
        // repository with a test-only second connection that production lacks.
        await configureSessionDatabaseTestGraph(env);
        mainDatabase = getIt.get<TenturaDb>();
        if (getIt.isRegistered<TenturaDb>(instanceName: 'auth')) {
          authDatabase = getIt.get<TenturaDb>(instanceName: 'auth');
        }
        sessionCase = getIt.get<SessionCase>();
        expect(env.pgPoolSettings.maxConnectionCount, 1);

        await session!.writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, 'Session isolation', @public_key)
'''),
          parameters: {
            'id': _accountId,
            'public_key': pgTestPublicKey('authisolation', 1),
          },
        );
        token = await sessionCase.createSession(accountId: _accountId);
        // Warm both connections so the measured path isolates queue contention.
        expect(await sessionCase.resolveAccountId(token), _accountId);
        await mainDatabase!.customSelect('SELECT 1').get();
      });

      tearDownAll(() async {
        if (authDatabase != null && !identical(authDatabase, mainDatabase)) {
          await authDatabase!.close();
        }
        await mainDatabase?.close();
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
        if (session != null) {
          await tearDownDisposablePgWriter(session: session!);
        }
      });

      test(
        'resolves a valid session in under 500 ms during a five-second main query',
        () async {
          final result = await _duringMainDatabaseSleep(
            mainDatabase!,
            () => sessionCase.resolveAccountId(token),
          );

          expect(result.value, _accountId);
          expect(
            result.elapsed,
            lessThan(_latencyBudget),
            reason:
                'Session resolution must use the independent auth connection.',
          );
        },
      );
    },
    skip: skipReason,
  );
}
