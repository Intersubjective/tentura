import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/domain/use_case/attention_cutover_case.dart';
import 'package:tentura_server/domain/use_case/trust_cutover_case.dart';

import 'di.dart';
import 'worker.dart';
import 'workers/web_worker.dart';

class App {
  ///
  /// Run App with given environment
  /// Default [Env.prod]
  ///
  Future<void> run([Env? env]) async {
    env ??= Env.prod();

    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await migrateDbSchema(connection);
    await connection.execute('ALTER EXTENSION pgmer2 UPDATE');
    // The boot-time maintenance sweep re-projects existing pairs, so a
    // changed value reaches MR shortly after start.
    await connection.execute(
      Sql.named(
        'INSERT INTO public.trust_config (key, value) '
        "VALUES ('noisy_wall_enabled', to_jsonb(@enabled::boolean)) "
        'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
      ),
      parameters: {'enabled': env.trustNoisyWallEnabled},
    );
    final getIt = await configureDependencies(env);
    await getIt.allReady();
    await getIt<TrustCutoverCase>().runIfPending();
    // U18a — D19's cutover, on the same boot hook as the trust cutover and
    // for the same reason: it is restartable, so an interrupted boot simply
    // resumes on the next one.
    await getIt<AttentionCutoverCase>().cutoverBackfillIfNeeded();
    await getIt.reset();
    await _uploadGraph(connection);
    await connection.close();

    final workers = await Future.wait([
      Worker.spawnTaskWorker(env: env),
      for (var i = 0; i < env.isolatesCount; i += 1)
        Worker.spawnWebWorker(env: env, debugName: 'Worker #$i'),
    ]);

    await _stopSignal();

    await Future.wait(workers.map((e) => e.close()));
  }

  ///
  /// Run App in Test environment with mocked repositories
  ///
  Future<void> runWithTestEnv({
    Future<void> Function(({SendPort sendPort, Env env}) params) worker =
        serveWeb,
  }) async {
    final receivePort = ReceivePort();
    final ready = Completer<SendPort>();
    receivePort.listen((dynamic message) {
      if (message is SendPort) ready.complete(message);
    });
    try {
      final running = worker((
        env: Env.test(),
        sendPort: receivePort.sendPort,
      ));
      // A worker that dies before it sends its SendPort must surface here.
      final commands = await Future.any([
        ready.future,
        running.then<SendPort>(
          (_) => throw StateError('Worker exited before it was ready'),
        ),
      ]);
      await _stopSignal();
      commands.send(null);
      await running;
    } finally {
      receivePort.close();
    }
  }

  Future<void> _stopSignal() async {
    final sigint = StreamIterator(ProcessSignal.sigint.watch());
    final sigterm = StreamIterator(ProcessSignal.sigterm.watch());
    try {
      await Future.any([sigint.moveNext(), sigterm.moveNext()]);
    } finally {
      await sigint.cancel();
      await sigterm.cancel();
    }
  }

  Future<void> _uploadGraph(Connection connection) async {
    try {
      // Until the trust cutover is done the graph must stay untouched.
      final done = await connection.execute(
        "SELECT 1 FROM trust_cutover_state WHERE id = 1 AND status = 'done'",
      );
      if (done.isEmpty) return;
      final edgesResult = await connection.execute(
        'SELECT count(*) FROM mr_edgelist()',
      );

      if (edgesResult.first.first == 0) {
        final initResult = await connection.execute(
          'SELECT meritrank_init()',
        );
        print('Graph uploaded [${initResult.first.first}]');
      } else {
        print('Graph already uploaded [${edgesResult.first.first}]');
      }
    } on Object catch (e, st) {
      // Allow the server to start even if MeritRank graph init fails.
      stderr
        ..writeln('Warning: MeritRank graph init skipped: $e')
        ..writeln(st);
    }
  }
}
