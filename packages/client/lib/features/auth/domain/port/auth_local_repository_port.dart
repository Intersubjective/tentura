import 'dart:async';

import 'package:tentura/features/auth/data/repository/auth_local_repository.dart' show AuthLocalRepository;
import 'package:tentura/features/auth/domain/entity/account_entity.dart';

/// Local auth / accounts (implemented by [AuthLocalRepository] in data layer).
abstract class AuthLocalRepositoryPort {
  Future<void> dispose();

  Stream<String> currentAccountChanges();

  Future<String> getSeedByAccountId(String id);

  Future<String> getCurrentAccountId();

  Future<List<AccountEntity>> getAccountsAll();

  Future<AccountEntity?> getAccountById(String id);

  Future<AccountEntity?> getCurrentAccount();

  Future<void> removeAccount(String id);

  Future<void> updateAccount(AccountEntity account);

  Future<void> setCurrentAccountId(String? id);

  Future<void> addAccount(String id, String seed, [String? title]);
}
