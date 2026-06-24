import 'dart:async';
import 'dart:isolate';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';

import '../di.dart';
import '../sentry/sentry_init.dart';

///
/// Serve delayed tasks from DB
///
Future<void> serveTask(({SendPort sendPort, Env env}) params) async {
  await initSentry(
    env: params.env,
    appRunner: () async {
      final receivePort = ReceivePort();
      params.sendPort.send(receivePort.sendPort);

      final getIt = await configureDependencies(params.env);
      final taskWorker = await getIt.getAsync<TaskWorkerCase>();
      unawaited(taskWorker.run());
      print('${Isolate.current.debugName} started at ${DateTime.timestamp()}');

      // First message means stop command
      await receivePort.first;

      receivePort.close();
      await taskWorker.dispose();
      await getIt.reset();
      params.sendPort.send(null);
      print('${Isolate.current.debugName} stoped at ${DateTime.timestamp()}');
    },
  );
}
