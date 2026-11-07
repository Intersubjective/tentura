import '../exception.dart';
import '../port/auth_local_repository_port.dart';
import '../port/auth_remote_repository_port.dart';

/// A saved account may use a cookie only when that cookie belongs to it.
Future<void> requireMatchingSessionAccount(
  AuthRemoteRepositoryPort remote,
  AuthLocalRepositoryPort local, {
  required String userId,
  required String sessionUserId,
}) async {
  if (sessionUserId != userId) {
    final account = await local.getAccountById(userId);
    await remote.signOut();
    await local.setCurrentAccountId(null);
    await local.removeAccount(userId);
    final displayName = account?.displayName ?? '';
    throw SessionAccountMismatchException(
      displayName.isEmpty ? userId : displayName,
    );
  }
}
