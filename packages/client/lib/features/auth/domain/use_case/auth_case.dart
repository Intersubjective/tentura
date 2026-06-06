import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import 'package:tentura/domain/port/device_push_port.dart';

import '../../data/service/web_handoff.dart';
import '../../data/service/web_post_sign_out.dart';
import '../entity/web_bootstrap_result.dart';
import '../port/auth_local_repository_port.dart';
import '../port/auth_remote_repository_port.dart';
import '../exception.dart';

@singleton
final class AuthCase extends UseCaseBase {
  AuthCase(
    this._authLocalRepository,
    this._authRemoteRepository,
    this._devicePushPort, {
    required super.env,
    required super.logger,
  });

  final AuthLocalRepositoryPort _authLocalRepository;

  final AuthRemoteRepositoryPort _authRemoteRepository;

  final DevicePushPort _devicePushPort;

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
  /// Signs up a new user.
  /// Returns the ID of the newly created and signed-in account.
  ///
  Future<String> signUp({
    required String displayName,
    required String invitationCode,
    String? handle,
  }) async {
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
  }

  ///
  /// Web only: consumes a landing -> app session handoff carried in the URL
  /// fragment (`#th=...`, captured before boot — see `docs/handoff-contract.md`).
  /// Writes the account seed to local storage and makes it current so the normal
  /// hydration path lands authenticated, then scrubs the fragment. Idempotent;
  /// a malformed/absent handoff is ignored and never blocks boot. No-op off web.
  ///
  Future<void> consumeHandoff() async {
    await bootstrapWebSession();
  }

  ///
  /// Web bootstrap: consume optional `#th=` handoff, probe session cookie, pick
  /// account id (fresh handoff wins over cookie). No-op handoff path off-web.
  ///
  Future<WebBootstrapResult> bootstrapWebSession({
    @visibleForTesting HandoffPayload? handoffForTest,
  }) async {
    final handoffPayload = handoffForTest ?? readHandoff();
    String? handoffUserId;
    if (handoffPayload != null) {
      try {
        await applyHandoff(handoffPayload);
        handoffUserId = handoffPayload.userId;
      } catch (e, s) {
        logger.warning('Failed to consume session handoff', e, s);
      } finally {
        scrubHandoff();
      }
    }

    final probe = await _probeSessionUserId();

    if (handoffUserId != null) {
      if (probe.userId != null && probe.userId != handoffUserId) {
        await _authRemoteRepository.clearSessionCookie();
      }
      await _authLocalRepository.setCurrentAccountId(handoffUserId);
      return WebBootstrapResult(
        currentAccountId: handoffUserId,
        freshHandoffUserId: handoffUserId,
        sessionUserId: probe.userId,
      );
    }

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
  /// Writes a handoff [payload] to local storage and makes it the current
  /// account. Idempotent: skips the insert when the account already exists
  /// (avoids the `InsertMode.insert` duplicate throw) and just re-activates it.
  ///
  @visibleForTesting
  Future<void> applyHandoff(HandoffPayload payload) async {
    final existing = await _authLocalRepository.getAccountById(payload.userId);
    if (existing == null) {
      await _authLocalRepository.addAccount(
        payload.userId,
        payload.seed,
        payload.displayName,
      );
    }
    await _authLocalRepository.setCurrentAccountId(payload.userId);
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
  Future<void> signIn({required String userId}) async {
    if (await _authLocalRepository.isSessionAccount(userId)) {
      await _authRemoteRepository.signInWithSession();
      await _authLocalRepository.setCurrentAccountId(userId);
      return;
    }
    final seed = await _authLocalRepository.getSeedByAccountId(userId);
    if (seed.isEmpty) {
      throw const AuthSeedIsWrongException();
    }
    await _authRemoteRepository.signIn(seed);
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
  Future<void> signOut() async {
    final currentId = await _authLocalRepository.getCurrentAccountId();
    if (currentId.isNotEmpty &&
        await _authLocalRepository.isSessionAccount(currentId)) {
      await _authRemoteRepository.sessionLogout();
    }
    await _devicePushPort.unregisterCurrentDevice();
    await _authRemoteRepository.signOut();
    await _authLocalRepository.setCurrentAccountId(null);
    final clearResult = await _authRemoteRepository.clearSessionCookie();
    redirectToLandingAfterSignOut(
      clearAcknowledged: clearResult.acknowledged,
    );
  }

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
