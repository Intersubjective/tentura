import '../../domain/port/auth_local_repository_port.dart';
import '../../domain/port/auth_remote_repository_port.dart';

/// Web sign-out: drop every locally stored account (seeds, session markers, rows).
/// The landing surface owns re-auth; stale device state must not survive logout.
Future<void> clearLocalAuthOnSignOut(AuthLocalRepositoryPort local) async {
  await local.clearAllAuthData();
}

Future<void> clearAllLocalAuthData(AuthLocalRepositoryPort local) async {
  await local.clearAllAuthData();
}

/// When a valid HttpOnly session cookie exists, prefer it over a stale local seed.
Future<bool> tryPreferCookieSessionSignIn(
  AuthRemoteRepositoryPort remote,
  AuthLocalRepositoryPort local,
  String userId,
) async {
  try {
    final sessionUserId = await remote.signInWithSession();
    if (sessionUserId != userId) {
      return false;
    }
    await local.addSessionAccount(userId);
    await local.setCurrentAccountId(userId);
    return true;
  } catch (_) {
    return false;
  }
}
