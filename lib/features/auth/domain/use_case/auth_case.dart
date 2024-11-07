import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../data/repository/auth_repository.dart';
import '../entity/account.dart';
import '../exception.dart';

@singleton
class AuthCase {
  AuthCase({
    required AuthRepository authRepository,
    required RemoteApiService remoteApiService,
  })  : _authRepository = authRepository,
        _remoteApiService = remoteApiService;

  final AuthRepository _authRepository;

  final RemoteApiService _remoteApiService;

  Stream<String> get currentAccountChanges =>
      _authRepository.currentAccountChanges();

  Future<String> getCurrentAccountId() => _authRepository.getCurrentAccountId();

  Future<Set<Account>> getAccountAll() => _authRepository.getAccountAll();

  Future<Account> addAccount(String seed) async {
    if (seed.isEmpty) throw const AuthSeedIsWrongException();
    final id = await _remoteApiService.signIn(seed: seed);
    if (id.isEmpty) throw const AuthIdIsWrongException();
    return _authRepository.putAccount(Account(id: id, seed: seed));
  }

  Future<Account> signUp() async {
    final (:id, :seed) = await _remoteApiService.signUp();
    await _authRepository.setCurrentAccountId(id);
    return _authRepository.putAccount(Account(id: id, seed: seed));
  }

  Future<Account> signIn(
    String id, {
    bool isPremature = false,
  }) async {
    final account = await _authRepository.getAccountById(id);
    if (account == null) throw const AuthIdNotFoundException();
    await _remoteApiService.signIn(
      prematureUserId: isPremature ? id : null,
      seed: account.seed,
    );
    await _authRepository.setCurrentAccountId(id);
    return account;
  }

  Future<void> signOut() async {
    await _remoteApiService.signOut();
    await _authRepository.setCurrentAccountId(null);
  }

  /// Remove account only from local storage
  Future<void> removeAccount(String id) async {
    await _remoteApiService.signOut();
    await _authRepository.removeAccountById(id);
    if (await _authRepository.getCurrentAccountId() == id) {
      await _authRepository.setCurrentAccountId(null);
    }
  }
}
