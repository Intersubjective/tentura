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
    final payload = readHandoff();
    if (payload == null) {
      return;
    }
    try {
      await applyHandoff(payload);
    } catch (e, s) {
      logger.warning('Failed to consume session handoff', e, s);
    } finally {
      scrubHandoff();
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
  /// Signs in with the account corresponding to the given [userId].
  /// Throws [AuthSeedIsWrongException] if the seed for the account is not found.
  ///
  Future<void> signIn({required String userId}) async {
    final seed = await _authLocalRepository.getSeedByAccountId(userId);
    if (seed.isEmpty) {
      throw const AuthSeedIsWrongException();
    }
    await _authRemoteRepository.signIn(seed);
    await _authLocalRepository.setCurrentAccountId(userId);
  }

  ///
  /// Signs out the current user.
  ///
  Future<void> signOut() async {
    await _devicePushPort.unregisterCurrentDevice();
    await _authRemoteRepository.signOut();
    await _authLocalRepository.setCurrentAccountId(null);
  }

  //
  static final _random = Random.secure();
}
