import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/data/repository/fcm_remote_repository.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';

@Singleton(
  as: FcmRemoteRepositoryPort,
  env: [
    Environment.test,
  ],
  order: 1,
)
class FcmRemoteRepositoryMock extends DisabledFcmRemoteRepository
    implements FcmRemoteRepositoryPort {
  FcmRemoteRepositoryMock() : super(Logger.root);
}
