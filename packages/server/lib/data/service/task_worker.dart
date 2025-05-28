import 'package:pg_job_queue/pg_job_queue.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';

import 'package:tentura_server/env.dart';

export 'package:pg_job_queue/pg_job_queue.dart' show JobStatus;

@singleton
class TaskWorker extends PgJobQueue {
  @FactoryMethod(preResolve: true)
  static Future<TaskWorker> create(Env env) async {
    final taskWorker = TaskWorker(
      await Connection.open(
        Endpoint(
          host: env.pgHost,
          port: env.pgPort,
          database: env.pgDatabase,
          username: env.pgUsername,
          password: env.pgPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      ),
    );
    await taskWorker.init();
    return taskWorker;
  }

  TaskWorker(this._connection, {super.table = 'tasks', super.uniqueId})
    : super(_connection);

  final Connection _connection;

  @disposeMethod
  Future<void> dispose() => _connection.close();
}
