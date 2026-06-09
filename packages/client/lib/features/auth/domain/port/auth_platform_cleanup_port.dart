import '../entity/auth_recovery_outcome.dart';
import 'auth_local_repository_port.dart';
import 'auth_remote_repository_port.dart';

/// Platform-specific auth cleanup, cookie preference, and post-reset navigation.
abstract class AuthPlatformCleanupPort {
  Future<void> clearLocalAuthOnSignOut(AuthLocalRepositoryPort local);

  Future<void> clearAllLocalAuthData(AuthLocalRepositoryPort local);

  Future<bool> tryPreferCookieSessionSignIn(
    AuthRemoteRepositoryPort remote,
    AuthLocalRepositoryPort local,
    String userId,
  );

  void applyRecoveryNavigation(AuthRecoveryOutcome outcome);

  void reloadAfterRejectedSession({required bool clearAcknowledged});

  void noteAuthenticatedBoot();

  void clearStaleSessionBrowserGuard();

  AuthRecoveryNavigation get signOutNavigationTarget;

  AuthRecoveryNavigation get resetNavigationTarget;

  /// Non-destructive recovery: drop active session pointer, keep seeds/accounts.
  Future<void> prepareForSignInAgain(AuthLocalRepositoryPort local);
}
