import 'package:injectable/injectable.dart';

import 'package:tentura_root/utils/utils.dart';

import 'package:tentura_server/data/mapper/task_status_mapper.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';

import '../service/task_worker.dart';

@LazySingleton(
  as: TaskRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
)
class TaskRepository implements TaskRepositoryPort {
  @FactoryMethod()
  static Future<TaskRepository> create(TaskWorker taskWorker) async =>
      TaskRepository(taskWorker);

  const TaskRepository(this._taskWorker);

  final TaskWorker _taskWorker;

  @override
  Future<T?> acquire<T extends TaskEntity>() async {
    switch (typeOf<T>()) {
      case const (TaskEntity<TaskCalculateImageHashDetails>):
        final task = await _taskWorker.acquire(queue: _queueCalculateImageHash);
        return task == null
            ? null
            : TaskEntity(
                    id: task.id,
                    status: taskStatusFromJobStatus(task.status),
                    details: TaskCalculateImageHashDetails.fromJson(
                      task.payload,
                    ),
                  )
                  as T;

      default:
        throw UnimplementedError();
    }
  }

  @override
  Future<String> schedule(TaskEntity task) => switch (task.details) {
    final TaskCalculateImageHashDetails details => _taskWorker.schedule(
      details.toJson(),
      queue: _queueCalculateImageHash,
    ),
    _ => throw UnimplementedError(),
  };

  @override
  Future<void> complete(String id) => _taskWorker.complete(id);

  @override
  Future<void> fail(String id) => _taskWorker.fail(id);

  static const _queueCalculateImageHash = 'calculate_image_hash';
}
