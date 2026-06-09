import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';
import 'package:synchronized/synchronized.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import 'package:tentura/domain/port/device_push_port.dart';

import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

import '../entity/auth_recovery_outcome.dart';
import '../entity/web_bootstrap_result.dart';
import '../port/auth_local_repository_port.dart';
import '../port/auth_platform_cleanup_port.dart';
import '../port/auth_remote_repository_port.dart';
import '../exception.dart';

@singleton
final class AuthCase extends UseCaseBase {
  AuthCase(
    this._authLocalRepository,
    this._authRemoteRepository,
    this._devicePushPort,
    this._platformCleanup,
    this._settingsRepository, {
    required super.env,
    required super.logger,
  });

  final AuthLocalRepositoryPort _authLocalRepository;

  final AuthRemoteRepositoryPort _authRemoteRepository;

  final DevicePushPort _devicePushPort;

  final AuthPlatformCleanupPort _platformCleanup;

  final SettingsRepositoryPort _settingsRepository;

  final _authTransitionLock = Lock();

  ///
  /// A stream that emits the current account ID whenever it changes.
  /// It immediately emits the last known account ID upon subscription.
  ///
  Stream<String> currentAccountChanges() =>
      _authLocalRepository.currentAccountChanges();

  ///
  /// Returns the ID of the currently signed-in account.
  ///
  Future<String> getCurrentAccountId() =>
      _authLocalRepository.getCurrentAccountId();

  ///
  /// True when any stored account is seed-only (no session marker).
  ///
  Future<bool> hasSeedOnlyLocalAccounts() async {
    for (final account in await _authLocalRepository.getAccountsAll()) {
      if (await _authLocalRepository.isSessionAccount(account.id)) {
        continue;
      }
      try {
        final seed = await _authLocalRepository.getSeedByAccountId(account.id);
        if (seed.isNotEmpty) {
          return true;
        }
      } on AuthIdNotFoundException {
        continue;
      }
    }
    return false;
  }

  ///
  /// Signs up a new user.
  /// Returns the ID of the newly created and signed-in account.
  ///
  Future<String> signUp({
    required String displayName,
    required String invitationCode,
    String? handle,
  }) =>
      _runAuthTransition(() async {
        final seed = base64UrlEncode(
          Uint8List.fromList(
            List<int>.generate(
              kSeedLength,
              (_) => _random.nextInt(256),
              growable: false,
            ),
          ),
        );
        final userId = await _authRemoteRepository.signUp(
          seed: seed,
          displayName: displayName,
          invitationCode: invitationCode,
          handle: handle,
        );
        await _authLocalRepository.addAccount(
          userId,
          seed,
          displayName,
        );
        await _authLocalRepository.setCurrentAccountId(userId);
        return userId;
      });

  ///
  /// Web bootstrap: probe the HttpOnly session cookie and pick the current
  /// account id. No-op cookie path off-web.
  ///
  Future<WebBootstrapResult> bootstrapWebSession() async {
    final probe = await _probeSessionUserId();

    if (probe.userId != null) {
      await _authLocalRepository.setCurrentAccountId(probe.userId);
      return WebBootstrapResult(
        currentAccountId: probe.userId!,
        sessionUserId: probe.userId,
      );
    }

    final localId = await getCurrentAccountId();
    return WebBootstrapResult(
      currentAccountId: localId,
      invalidSessionCookieRejected: probe.invalidSessionCookieRejected,
      sessionCookieClearAcknowledged: probe.sessionCookieClearAcknowledged,
    );
  }

  Future<_SessionProbeResult> _probeSessionUserId() async {
    try {
      final userId = await _authRemoteRepository.signInWithSession();
      final existing = await _authLocalRepository.getAccountById(userId);
      if (existing == null) {
        await _authLocalRepository.addSessionAccount(userId);
      }
      return _SessionProbeResult(userId: userId);
    } on SessionAuthRejectedException {
      final clearResult = await _authRemoteRepository.clearSessionCookie();
      await _clearGhostSessionOnlyLocalId();
      return _SessionProbeResult(
        invalidSessionCookieRejected: true,
        sessionCookieClearAcknowledged: clearResult.acknowledged,
      );
    } catch (e, s) {
      logger.fine('No cookie session to bootstrap', e, s);
      return const _SessionProbeResult();
    }
  }

  Future<void> _clearGhostSessionOnlyLocalId() async {
    final currentId = await getCurrentAccountId();
    if (currentId.isEmpty) return;
    if (!await _authLocalRepository.isSessionAccount(currentId)) return;
    try {
      await _authLocalRepository.getSeedByAccountId(currentId);
    } on AuthIdNotFoundException {
      await _authLocalRepository.setCurrentAccountId(null);
    }
  }

  ///
  /// Web: bootstrap from HttpOnly session cookie when present (Google OAuth).
  /// Returns the account id or null when no valid cookie session exists.
  ///
  Future<String?> tryBootstrapSession() async {
    final probe = await _probeSessionUserId();
    final userId = probe.userId;
    if (userId == null) {
      return null;
    }
    await _authLocalRepository.setCurrentAccountId(userId);
    return userId;
  }

  ///
  /// Signs in with the account corresponding to the given [userId].
  /// Throws [AuthSeedIsWrongException] if the seed for the account is not found.
  ///
  Future<void> signIn({required String userId}) => _runAuthTransition(() async {
    if (await _authLocalRepository.isSessionAccount(userId)) {
      await _signInWithSession(userId);
      return;
    }
    if (await _platformCleanup.tryPreferCookieSessionSignIn(
      _authRemoteRepository,
      _authLocalRepository,
      userId,
    )) {
      return;
    }
    final seed = await _authLocalRepository.getSeedByAccountId(userId);
    if (seed.isEmpty) {
      throw const AuthSeedIsWrongException();
    }
    await _authRemoteRepository.signIn(seed);
    await _authLocalRepository.setCurrentAccountId(userId);
  });

  Future<void> _signInWithSession(String userId) async {
    await _authRemoteRepository.signInWithSession();
    await _authLocalRepository.setCurrentAccountId(userId);
  }

  ///
  /// Converge seed Bearer auth to HttpOnly session cookie (web preview CORS).
  ///
  Future<void> establishSessionCookie() =>
      _authRemoteRepository.establishSessionFromBearer();

  ///
  /// Signs out the current user.
  ///
  Future<AuthRecoveryOutcome> signOut() => _runAuthTransition(() async {
    try {
      await _devicePushPort.unregisterCurrentDevice();
    } catch (e, s) {
      logger.fine('Push unregister best-effort failed', e, s);
    }
    try {
      await _authRemoteRepository.signOut();
    } catch (e, s) {
      logger.fine('Remote signOut best-effort failed', e, s);
    }
    await _platformCleanup.clearLocalAuthOnSignOut(_authLocalRepository);
    var cookieAcknowledged = false;
    try {
      final clearResult = await _authRemoteRepository.clearSessionCookie();
      cookieAcknowledged = clearResult.acknowledged;
    } catch (e, s) {
      logger.fine('Session cookie clear best-effort failed', e, s);
    }
    return AuthRecoveryOutcome(
      navigation: _platformCleanup.signOutNavigationTarget,
      sessionCookieClearAcknowledged: cookieAcknowledged,
    );
  });

  ///
  /// Recovery: drop in-memory auth and cookies; keep local accounts/seeds.
  ///
  Future<AuthRecoveryOutcome> signInAgain() => _runAuthTransition(() async {
    try {
      await _authRemoteRepository.signOut();
    } catch (e, s) {
      logger.fine('Remote signOut best-effort failed', e, s);
    }
    var cookieAcknowledged = false;
    try {
      final clearResult = await _authRemoteRepository.clearSessionCookie();
      cookieAcknowledged = clearResult.acknowledged;
    } catch (e, s) {
      logger.fine('Session cookie clear best-effort failed', e, s);
    }
    await _platformCleanup.prepareForSignInAgain(_authLocalRepository);
    return AuthRecoveryOutcome(
      navigation: _platformCleanup.resetNavigationTarget,
      sessionCookieClearAcknowledged: cookieAcknowledged,
    );
  });

  ///
  /// Nuclear reset: wipe all local auth state and best-effort remote logout.
  ///
  Future<AuthRecoveryOutcome> resetLocalAuthState() =>
      _runAuthTransition(() async {
        try {
          await _devicePushPort.unregisterCurrentDevice();
        } catch (e, s) {
          logger.fine('Push unregister best-effort failed', e, s);
        }
        try {
          await _settingsRepository.setLastFcmRegistration(null);
        } catch (e, s) {
          logger.fine('FCM registration clear best-effort failed', e, s);
        }
        try {
          await _authRemoteRepository.signOut();
        } catch (e, s) {
          logger.fine('Remote signOut best-effort failed', e, s);
        }
        await _platformCleanup.clearAllLocalAuthData(_authLocalRepository);
        _platformCleanup.clearStaleSessionBrowserGuard();
        var cookieAcknowledged = false;
        try {
          final clearResult = await _authRemoteRepository.clearSessionCookie();
          cookieAcknowledged = clearResult.acknowledged;
        } catch (e, s) {
          logger.fine('Session cookie clear best-effort failed', e, s);
        }
        return AuthRecoveryOutcome(
          navigation: _platformCleanup.resetNavigationTarget,
          sessionCookieClearAcknowledged: cookieAcknowledged,
        );
      });

  void applyRecoveryNavigation(AuthRecoveryOutcome outcome) =>
      _platformCleanup.applyRecoveryNavigation(outcome);

  void reloadAfterRejectedSession({required bool clearAcknowledged}) =>
      _platformCleanup.reloadAfterRejectedSession(
        clearAcknowledged: clearAcknowledged,
      );

  void noteAuthenticatedBoot() => _platformCleanup.noteAuthenticatedBoot();

  Future<T> _runAuthTransition<T>(Future<T> Function() action) =>
      _authTransitionLock.synchronized(action);

  //
  static final _random = Random.secure();
}

final class _SessionProbeResult {
  const _SessionProbeResult({
    this.userId,
    this.invalidSessionCookieRejected = false,
    this.sessionCookieClearAcknowledged = false,
  });

  final String? userId;
  final bool invalidSessionCookieRejected;
  final bool sessionCookieClearAcknowledged;
}
