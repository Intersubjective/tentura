import 'dart:async';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/data/service/local_secure_storage.dart';

import '../../domain/entity/account_entity.dart';
import '../../domain/exception.dart';
import '../../domain/port/auth_local_repository_port.dart';
import '../mapper/account_mapper.dart';

@Singleton(
  as: AuthLocalRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class AuthLocalRepository implements AuthLocalRepositoryPort {
  AuthLocalRepository(
    this._logger,
    this._database,
    this._localSecureStorage,
  );

  final Logger _logger;

  final Database _database;

  final LocalSecureStorage _localSecureStorage;

  final _controllerIdChanges = StreamController<String>.broadcast();

  String _currentAccountId = '';

  //
  //
  @override
  @disposeMethod
  Future<void> dispose() async {
    await _controllerIdChanges.close();
  }

  //
  //
  @override
  Stream<String> currentAccountChanges() async* {
    yield _currentAccountId.isNotEmpty
        ? _currentAccountId
        : await getCurrentAccountId();

    yield* _controllerIdChanges.stream;
  }

  //
  //
  @override
  Future<String> getSeedByAccountId(String id) async =>
      await _localSecureStorage.read(_getAccountKey(id)) ??
      (throw const AuthIdNotFoundException());

  //
  //
  @override
  Future<String> getCurrentAccountId() async => _currentAccountId.isEmpty
      ? _localSecureStorage
            .read(_currentAccountKey)
            .then((v) => _currentAccountId = v ?? '')
      : _currentAccountId;

  //
  //
  @override
  Future<List<AccountEntity>> getAccountsAll() async => [
    for (final account in await _database.managers.accounts.get())
      accountModelToEntity(account),
  ];

  //
  //
  @override
  Future<AccountEntity?> getAccountById(String id) => _database
      .managers
      .accounts
      .filter((f) => f.id.equals(id))
      .getSingleOrNull()
      .then(
        (e) => e == null ? null : accountModelToEntity(e),
      );

  //
  //
  @override
  Future<AccountEntity?> getCurrentAccount() => _currentAccountId.isEmpty
      ? Future.value()
      : _database.managers.accounts
            .filter((f) => f.id.equals(_currentAccountId))
            .getSingleOrNull()
            .then(
              (e) => e == null ? null : accountModelToEntity(e),
            );

  ///
  /// Remove account only from local storage
  ///
  @override
  Future<void> removeAccount(String id) async {
    await _database.managers.accounts.filter((e) => e.id.equals(id)).delete();
    await _localSecureStorage.delete(_getAccountKey(id));
  }

  //
  //
  @override
  Future<void> updateAccount(AccountEntity account) => _database
      .managers
      .accounts
      .filter((f) => f.id.equals(account.id))
      .update(
        (o) => o(
          title: Value(account.title),
          fcmTokenUpdatedAt: Value(account.fcmTokenUpdatedAt),
          imageId: Value(account.image?.id ?? ''),
          blurHash: Value(account.image?.blurHash ?? ''),
          height: Value(account.image?.height ?? 0),
          width: Value(account.image?.width ?? 0),
        ),
      );

  //
  //
  @override
  Future<void> setCurrentAccountId(String? id) async {
    await _localSecureStorage.write(
      _currentAccountKey,
      _currentAccountId = id ?? '',
    );
    _controllerIdChanges.add(_currentAccountId);
    _logger.info('Current User Id: $id');
  }

  //
  //
  @override
  Future<void> addAccount(String id, String seed, [String? title]) async {
    await _localSecureStorage.write(_getAccountKey(id), seed);
    await _database.managers.accounts.create(
      (o) => title == null ? o(id: id) : o(id: id, title: Value(title)),
      mode: InsertMode.insert,
    );
  }

  static const _repositoryKey = 'Auth';

  static const _currentAccountKey = '$_repositoryKey:currentAccountId';

  //
  static String _getAccountKey(String id) => '$_repositoryKey:Id:$id';
}
