import 'dart:async';
import 'dart:isolate';

import 'package:tentura_server/env.dart';

import 'workers/task_worker.dart';
import 'workers/web_worker.dart';

class Worker {
  static Future<Worker> spawnWebWorker({
    required Env env,
    String debugName = 'Web worker',
  }) => _spawn(env: env, debugName: debugName, worker: serveWeb);

  static Future<Worker> spawnTaskWorker({
    required Env env,
    String debugName = 'Task worker',
  }) => _spawn(env: env, debugName: debugName, worker: serveTask);

  Worker._(this._isolate, this._responses, this._commands);

  final ReceivePort _responses;

  final SendPort _commands;

  final Isolate _isolate;

  Future<void> close() async {
    _commands.send(null);
    await _responses.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          print('Timeout on close isolate [${Isolate.current.debugName}]'),
    );
    _responses.close();
    _isolate.kill();
  }

  static Future<Worker> _spawn({
    required Env env,
    required String debugName,
    required Future<void> Function(({SendPort sendPort, Env env})) worker,
  }) async {
    final initPort = RawReceivePort(null, debugName);
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (dynamic commandPort) {
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort as SendPort,
      ));
    };

    try {
      final isolate = await Isolate.spawn(
        worker,
        (sendPort: initPort.sendPort, env: env),
        debugName: debugName,
        errorsAreFatal: false,
      );
      final (ReceivePort receivePort, SendPort sendPort) =
          await connection.future;
      return Worker._(isolate, receivePort, sendPort);
    } catch (e) {
      print(e);
      initPort.close();
      rethrow;
    }
  }
}
