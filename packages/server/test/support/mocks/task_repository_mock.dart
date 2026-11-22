import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

@LazySingleton(
  as: TaskRepositoryPort,
  env: [Environment.test],
)
class TaskRepositoryMock implements TaskRepositoryPort {
  @FactoryMethod()
  static Future<TaskRepositoryMock> create() =>
      Future.value(TaskRepositoryMock());

  @override
  Future<T?> acquire<T extends TaskEntity>() {
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
  Future<String> schedule(TaskEntity task) {
    throw UnimplementedError();
  }
}
