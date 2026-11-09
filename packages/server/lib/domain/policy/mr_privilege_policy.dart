import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

/// The MeritRank operator rule: an admin role passes without a user lookup;
/// otherwise the user must hold [UserPrivileges.mrInit].
///
/// Throws [UnauthorizedException] when neither holds. Used by every
/// MeritRank maintenance entry point (init/reset, star and full refresh).
Future<void> ensureMrPrivilege(
  UserRepositoryPort users, {
  required String userId,
  Iterable<UserRoles>? userRoles,
}) async {
  if (userRoles != null && userRoles.contains(UserRoles.admin)) return;
  if ((await users.getById(userId)).hasPrivilege(UserPrivileges.mrInit)) {
    return;
  }
  throw const UnauthorizedException();
}
