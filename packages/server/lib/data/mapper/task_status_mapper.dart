import 'package:tentura_server/domain/entity/task_entity.dart';

import '../service/task_worker.dart' show JobStatus;

TaskStatus taskStatusFromJobStatus(JobStatus status) => switch (status) {
  JobStatus.scheduled => TaskStatus.scheduled,
  JobStatus.completed => TaskStatus.completed,
  JobStatus.acquired => TaskStatus.acquired,
  JobStatus.failed => TaskStatus.failed,
};
