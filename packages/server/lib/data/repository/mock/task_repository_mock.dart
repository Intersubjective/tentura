import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/task_entity.dart';

import '../tasks_repository.dart';

@Singleton(
  as: TaskRepository,
  env: [Environment.test],
)
class TaskRepositoryMock implements TaskRepository {
  @FactoryMethod()
  static Future<TaskRepositoryMock> create() =>
      Future.value(TaskRepositoryMock());

  @override
  Future<T?> acquire<T extends TaskEntity<TaskDetails>>() {
    throw UnimplementedError();
  }

  @override
  Future<void> complete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> fail(String id) {
    throw UnimplementedError();
  }

  @override
  Future<String> schedule(TaskEntity<TaskDetails> task) {
    throw UnimplementedError();
  }
}
