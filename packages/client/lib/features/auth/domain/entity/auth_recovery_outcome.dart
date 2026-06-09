/// Where the UI should navigate after an auth recovery operation completes.
enum AuthRecoveryNavigation {
  none,
  webInviteLanding,
  nativeLogin,
  nativeBack,
}

/// Result of sign-out or reset-local-auth orchestration.
class AuthRecoveryOutcome {
  const AuthRecoveryOutcome({
    this.navigation = AuthRecoveryNavigation.none,
    this.sessionCookieClearAcknowledged = false,
  });

  final AuthRecoveryNavigation navigation;
  final bool sessionCookieClearAcknowledged;
}
