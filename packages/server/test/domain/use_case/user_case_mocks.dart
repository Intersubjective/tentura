import 'package:mockito/annotations.dart';

import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

@GenerateMocks([
  UserRepositoryPort,
  ImageRepositoryPort,
  TaskRepositoryPort,
])
void main() {}
