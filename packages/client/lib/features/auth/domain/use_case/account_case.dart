import 'dart:async';
import 'dart:convert';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/sentry/auth_telemetry.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../port/auth_local_repository_port.dart';
import '../port/auth_remote_repository_port.dart';
import '../entity/account_entity.dart';
import '../exception.dart';

@singleton
final class AccountCase extends UseCaseBase {
  AccountCase(
    this._authLocalRepository,
    this._authRemoteRepository,
    this._platformRepository,
    this._profileRemoteRepository, {
    required super.env,
    required super.logger,
  });

  final AuthLocalRepositoryPort _authLocalRepository;

  final AuthRemoteRepositoryPort _authRemoteRepository;

  final PlatformRepositoryPort _platformRepository;

  final ProfileRepositoryPort _profileRemoteRepository;

  Stream<RepositoryEvent<Profile>> get profileChanges =>
      _profileRemoteRepository.changes;

  //
  //
  Future<void> openInviteEmailUrl() => _platformRepository.launchUri(
    Uri(
      scheme: 'mailto',
      path: env.inviteEmail,
    ),
  );

  //
  //
  Future<String> getSeedFromClipboard() async {
    try {
      return normalizeSeed(await _platformRepository.getStringFromClipboard());
    } catch (_) {
      throw const AuthSeedIsWrongException();
    }
  }

  //
  //
  Future<String> getCodeFromClipboard({
    String prefix = '',
  }) async {
    final text = await _platformRepository.getStringFromClipboard();
    final code = extractInviteCodeFromText(text, prefix: prefix);
    if (code != null) {
      return code;
    }
    throw const InvitationCodeIsWrongException();
  }

  //
  //
  Future<String> getSeedByAccountId(String id) =>
      _authLocalRepository.getSeedByAccountId(id);

  ///
  /// Returns the device seed when [id] is a local seed account; null for
  /// session/OAuth-only accounts (no seed stored).
  ///
  Future<String?> tryGetSeedForAccount(String id) async {
    if (await _authLocalRepository.isSessionAccount(id)) {
      return null;
    }
    try {
      final seed = await _authLocalRepository.getSeedByAccountId(id);
      return seed.isEmpty ? null : seed;
    } catch (_) {
      return null;
    }
  }

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
  /// Returns a list of all locally stored user profiles.
  ///
  Future<List<AccountEntity>> getAccountsAll() =>
      _authLocalRepository.getAccountsAll();

  ///
  /// Retrieves a user profile by its [id].
  /// Returns `null` if no account with the given [id] is found.
  ///
  Future<AccountEntity?> getAccountById(String id) =>
      _authLocalRepository.getAccountById(id);

  ///
  /// Add account to local storage and signs in
  ///
  // TBD: add gql node to get profile data by auth request JWT
  //      to prevent signIn\signOut flow?
  Future<AccountEntity> addAccount(String seed) async {
    final seedNormalized = normalizeSeed(seed);
    final userId = await _authRemoteRepository.signIn(seedNormalized);
    await _authLocalRepository.addAccount(
      userId,
      seedNormalized,
    );

    final profile = await _profileRemoteRepository.fetchById(userId);
    await _authRemoteRepository.signOut();

    return fromProfile(profile);
  }

  ///
  /// Validates [seed], signs in remotely (sets session cookie on web),
  /// upserts local seed-backed account, and makes it current.
  ///
  Future<AccountEntity> recoverFromSeedAndSignIn(
    String seed, {
    String? authAttemptId,
  }) async {
    String seedNormalized;
    try {
      seedNormalized = normalizeSeed(seed);
    } on AuthSeedIsWrongException catch (e) {
      await captureSeedRecoveryFailed(
        authOutcome: 'invalid_seed',
        authAttemptId: authAttemptId,
        error: e,
      );
      rethrow;
    }
    try {
      final userId = await _authRemoteRepository.signIn(
        seedNormalized,
        authAttemptId: authAttemptId,
      );
      Profile profile;
      try {
        profile = await _profileRemoteRepository.fetchById(userId);
      } catch (e, st) {
        await captureSeedRecoveryFailed(
          authOutcome: 'profile_fetch_failed',
          authAttemptId: authAttemptId,
          error: e,
          stackTrace: st,
        );
        rethrow;
      }
      final account = fromProfile(profile);
      try {
        await _authLocalRepository.upsertAccountWithSeed(
          userId,
          seedNormalized,
          profile.displayName,
        );
        await _authLocalRepository.updateAccount(account);
        await _authLocalRepository.setCurrentAccountId(userId);
      } catch (e, st) {
        await captureSeedRecoveryFailed(
          authOutcome: 'local_store_failed',
          authAttemptId: authAttemptId,
          error: e,
          stackTrace: st,
        );
        rethrow;
      }
      return account;
    } on SessionHttpException {
      rethrow;
    } catch (e, st) {
      await captureSeedRecoveryFailed(
        authOutcome: 'remote_sign_in_failed',
        authAttemptId: authAttemptId,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  ///
  /// Normalizes a backed-up seed to url-safe base64 of exactly [kSeedLength] bytes.
  ///
  static String normalizeSeed(String seed) {
    final trimmed = seed.trim();
    if (trimmed.isEmpty) {
      throw const AuthSeedIsWrongException();
    }
    try {
      final bytes = base64Decode(_base64Padded(trimmed));
      if (bytes.length != kSeedLength) {
        throw const AuthSeedIsWrongException();
      }
      return base64UrlEncode(bytes);
    } on AuthSeedIsWrongException {
      rethrow;
    } catch (_) {
      throw const AuthSeedIsWrongException();
    }
  }

  ///
  /// Removes an account from local storage, keeps it on remote server
  ///
  Future<void> removeAccount(String id) =>
      _authLocalRepository.removeAccount(id);

  ///
  /// Updates the profile information for an existing [account].
  ///
  Future<void> updateAccount(AccountEntity account) =>
      _authLocalRepository.updateAccount(account);

  //
  //
  static Profile fromAccountEntity(AccountEntity account) => Profile(
    id: account.id,
    displayName: account.displayName,
    image: account.image,
  );

  //
  //
  static AccountEntity fromProfile(Profile profile) => AccountEntity(
    id: profile.id,
    displayName: profile.displayName,
    image: profile.image,
  );

  //
  //
  static String _base64Padded(String value) => switch (value.length % 4) {
    2 => '$value==',
    3 => '$value=',
    _ => value,
  };
}
