import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/auth_remote_repository.dart';
import '../../data/repository/auth_local_repository.dart';
import '../exception.dart';

@singleton
final class AuthCase extends UseCaseBase {
  AuthCase(
    this._authLocalRepository,
    this._authRemoteRepository, {
    required super.env,
    required super.logger,
  });

  final AuthLocalRepository _authLocalRepository;

  final AuthRemoteRepository _authRemoteRepository;

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
    required String title,
    required String invitationCode,
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
      title: title,
      invitationCode: invitationCode,
    );
    await _authLocalRepository.addAccount(
      userId,
      seed,
      title,
    );
    await _authLocalRepository.setCurrentAccountId(userId);
    return userId;
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
  Future<void> signOut() => Future.wait([
    _authLocalRepository.setCurrentAccountId(null),
    _authRemoteRepository.signOut(),
  ]);

  //
  static final _random = Random.secure();
}
