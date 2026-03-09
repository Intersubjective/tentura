import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/data/repository/user_presence_repository.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';

export 'package:tentura_root/domain/enums.dart';

@Injectable(order: 2)
class UserPresenceCase {
  UserPresenceCase(
    this._userPresenceRepository,
  );

  final UserPresenceRepository _userPresenceRepository;

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
