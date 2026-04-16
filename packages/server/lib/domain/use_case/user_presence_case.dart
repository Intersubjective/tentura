import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';

import '_use_case_base.dart';

export 'package:tentura_root/domain/enums.dart';

@Injectable(order: 2)
final class UserPresenceCase extends UseCaseBase {
  UserPresenceCase(
    this._userPresenceRepository, {
    required super.env,
    required super.logger,
  });

  final UserPresenceRepositoryPort _userPresenceRepository;

  //
  //
  Future<UserPresenceEntity?> get(String userId) =>
      _userPresenceRepository.get(userId);

  //
  //
  Future<void> touch({
    required String userId,
  }) => _userPresenceRepository.update(
    userId,
    lastSeenAt: DateTime.timestamp(),
  );

  //
  //
  Future<void> setStatus({
    required String userId,
    required UserPresenceStatus status,
  }) => _userPresenceRepository.update(
    userId,
    status: status,
    lastSeenAt: DateTime.timestamp(),
  );
}
