import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/domain/entity/auth_recovery_outcome.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_platform_cleanup_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';

import '../../features/auth/data/service/web_auth_sign_out_cleanup.dart';
import '../../features/auth/data/service/web_bootstrap_policy.dart' as bootstrap_policy;
import '../../features/auth/data/service/web_post_sign_out.dart';
import '../../features/auth/data/service/web_rejected_session_redirect.dart';

@Singleton(as: AuthPlatformCleanupPort)
final class AuthPlatformCleanup implements AuthPlatformCleanupPort {
  @override
  AuthRecoveryNavigation get signOutNavigationTarget =>
      kIsWeb ? AuthRecoveryNavigation.webInviteLanding : AuthRecoveryNavigation.nativeBack;

  @override
  AuthRecoveryNavigation get resetNavigationTarget =>
      kIsWeb ? AuthRecoveryNavigation.webInviteLanding : AuthRecoveryNavigation.nativeLogin;

  @override
  Future<void> clearLocalAuthOnSignOut(AuthLocalRepositoryPort local) =>
      clearLocalAuthOnSignOutImpl(local);

  @override
  Future<void> clearAllLocalAuthData(AuthLocalRepositoryPort local) =>
      clearAllLocalAuthDataImpl(local);

  @override
  Future<bool> tryPreferCookieSessionSignIn(
    AuthRemoteRepositoryPort remote,
    AuthLocalRepositoryPort local,
    String userId,
  ) =>
      tryPreferCookieSessionSignInImpl(remote, local, userId);

  @override
  Future<void> prepareForSignInAgain(AuthLocalRepositoryPort local) async {
    await local.setCurrentAccountId(null);
  }

  @override
  void applyRecoveryNavigation(AuthRecoveryOutcome outcome) {
    switch (outcome.navigation) {
      case AuthRecoveryNavigation.webInviteLanding:
        redirectToLandingAfterSignOut(
          clearAcknowledged: outcome.sessionCookieClearAcknowledged,
        );
      case AuthRecoveryNavigation.nativeLogin:
      case AuthRecoveryNavigation.nativeBack:
      case AuthRecoveryNavigation.none:
        break;
    }
  }

  @override
  void reloadAfterRejectedSession({required bool clearAcknowledged}) {
    reloadAfterRejectedSessionImpl(clearAcknowledged: clearAcknowledged);
  }

  @override
  void noteAuthenticatedBoot() {
    noteAuthenticatedBootImpl();
  }

  @override
  void clearStaleSessionBrowserGuard() {
    clearStaleSessionBrowserGuardImpl();
  }

  @override
  bool get skipSessionCookieBootstrap =>
      bootstrap_policy.skipSessionCookieBootstrap;
}

Future<void> clearLocalAuthOnSignOutImpl(AuthLocalRepositoryPort local) =>
    clearLocalAuthOnSignOut(local);

Future<void> clearAllLocalAuthDataImpl(AuthLocalRepositoryPort local) =>
    clearAllLocalAuthData(local);

Future<bool> tryPreferCookieSessionSignInImpl(
  AuthRemoteRepositoryPort remote,
  AuthLocalRepositoryPort local,
  String userId,
) =>
    tryPreferCookieSessionSignIn(remote, local, userId);

void reloadAfterRejectedSessionImpl({required bool clearAcknowledged}) {
  reloadAfterRejectedSession(clearAcknowledged: clearAcknowledged);
}

void noteAuthenticatedBootImpl() {
  noteAuthenticatedBoot();
}

void clearStaleSessionBrowserGuardImpl() {
  clearStaleSessionBrowserGuard();
}
