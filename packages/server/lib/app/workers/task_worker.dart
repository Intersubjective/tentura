import 'dart:async';
import 'dart:isolate';

import 'package:tentura_server/data/service/pg_notification_service.dart';
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
      final notifications = await getIt.getAsync<PgNotificationService>();
      final mergeWakes = await notifications.watchPhantomMergeJobs();
      final subscription = mergeWakes.listen(
        (_) => taskWorker.nudgePhantomMerges(),
      );
      unawaited(taskWorker.run());
      print('${Isolate.current.debugName} started at ${DateTime.timestamp()}');

      // First message means stop command
      await receivePort.first;

      receivePort.close();
      await subscription.cancel();
      await taskWorker.dispose();
      await getIt.reset();
      params.sendPort.send(null);
      print('${Isolate.current.debugName} stoped at ${DateTime.timestamp()}');
    },
  );
}
