import '../../domain/port/auth_local_repository_port.dart';
import '../../domain/port/auth_remote_repository_port.dart';

/// Off-web: only clear the active account pointer; keep stored accounts/seeds.
Future<void> clearLocalAuthOnSignOut(AuthLocalRepositoryPort local) =>
    local.setCurrentAccountId(null);

/// Off-web: remove all auth rows/keys from local storage.
Future<void> clearAllLocalAuthData(AuthLocalRepositoryPort local) =>
    local.clearAllAuthData();

/// Off-web: session preference is handled via [AuthLocalRepositoryPort.isSessionAccount].
Future<bool> tryPreferCookieSessionSignIn(
  AuthRemoteRepositoryPort remote,
  AuthLocalRepositoryPort local,
  String userId,
) async =>
    false;

void clearStaleSessionBrowserGuardImpl() {}
