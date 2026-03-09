import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

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
  Future<void> runWithTestEnv() async {
    final receivePort = ReceivePort();
    unawaited(
      serveWeb((
        env: Env.test(),
        sendPort: receivePort.sendPort,
      )),
    );
    await _stopSignal();
    receivePort.sendPort.send(null);
  }

  //
  //
  Future<void> _stopSignal() => Future.any([
    ProcessSignal.sigint.watch().first,
    ProcessSignal.sigterm.watch().first,
  ]);

  //
  //
  Future<void> _uploadGraph(Connection connection) async {
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
  }
}
