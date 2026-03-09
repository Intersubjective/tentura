import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_entity.freezed.dart';
part 'task_entity.g.dart';

enum TaskStatus { scheduled, acquired, completed, failed }

abstract class TaskDetails {}

class TaskEntity<T extends TaskDetails> {
  const TaskEntity({
    required this.details,
    this.id = '',
    this.status = TaskStatus.scheduled,
  });

  final String id;

  final T details;

  final TaskStatus status;
}

@freezed
abstract class TaskCalculateImageHashDetails
    with _$TaskCalculateImageHashDetails
    implements TaskDetails {
  const factory TaskCalculateImageHashDetails({required String imageId}) =
      _TaskCalculateImageHashDetails;

  const TaskCalculateImageHashDetails._();

  factory TaskCalculateImageHashDetails.fromJson(Map<String, dynamic> json) =>
      _$TaskCalculateImageHashDetailsFromJson(json);
}
