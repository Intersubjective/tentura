import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/data/service/task_worker.dart';
import 'package:tentura_server/env.dart';

final class _UnusedTaskWorker implements TaskWorker {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _UnusedPgNotifications implements PgNotificationService {
  @override
  Stream<String> get entityChangeNotifications => const Stream.empty();

  @override
  Stream<PgNotificationRecovery> get recoveryNotifications =>
      const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Resolve the generated dev/prod graph with unrelated background I/O stubbed.
/// Session repositories, use cases, and database bindings remain unmodified.
Future<void> configureSessionDatabaseTestGraph(Env env) async {
  getIt
    ..skipDoubleRegistration = true
    ..registerLazySingletonAsync<TaskWorker>(() async => _UnusedTaskWorker())
    ..registerSingletonAsync<PgNotificationService>(
      () async => _UnusedPgNotifications(),
    );
  await getIt.getAsync<TaskWorker>();
  await getIt.getAsync<PgNotificationService>();
  await configureDependencies(env);
  await getIt.allReady(ignorePendingAsyncCreation: true);
}
