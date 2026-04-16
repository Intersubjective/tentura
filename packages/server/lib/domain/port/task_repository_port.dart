import 'package:tentura_server/domain/entity/task_entity.dart';

abstract class TaskRepositoryPort {
  Future<T?> acquire<T extends TaskEntity>();

  Future<String> schedule(TaskEntity task);

  Future<void> complete(String id);

  Future<void> fail(String id);
}
