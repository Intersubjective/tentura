import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/data/database/reopening_query_executor.dart';
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/auth/domain/entity/account_entity.dart';
import 'package:tentura/features/home/data/repository/home_orientation_preferences_repository.dart';

/// The statements that fail in the field return this generic SQLite message
/// (result code 1), not "no such table" or "no such column".
const _logicError = 'SQL logic error';

const _accountId = 'U563b1646f6ff';
const _userId = 'Uec81add732dc';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('local database after a generic SQL logic error', () {
    test('home activation flag is saved and the account remains', () async {
      final app = await _openApp(_homeActivationWrite);

      await _seedAccount(app, 'Alice');
      await app.database
          .into(app.database.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'home:activated:$_userId',
              valueBool: const Value(false),
            ),
          );
      app.poison.arm();

      await app.home.setActivated(userId: _userId);

      expect(await app.home.isActivated(userId: _userId), isTrue);
      expect(await _displayNames(app), ['Alice']);
      expect(await _userVersion(app.database), 5);
      expect(app.poison.fired, isTrue);
    });

    test('saved accounts stay listed with their display names', () async {
      final app = await _openApp(_accountList);

      await _seedAccount(app, 'Alice');
      app.poison.arm();

      expect(await _displayNames(app), ['Alice']);
      expect(await _userVersion(app.database), 5);
      expect(app.poison.fired, isTrue);
    });

    test('account display name update is kept', () async {
      final app = await _openApp(_accountUpdate);

      await _seedAccount(app, 'Ada');
      app.poison.arm();

      await app.auth.updateAccount(
        const AccountEntity(id: _accountId, displayName: 'Alice'),
      );

      expect(await _displayNames(app), ['Alice']);
      expect(await _userVersion(app.database), 5);
      expect(app.poison.fired, isTrue);
    });

    test('a saved settings flag still reads back', () async {
      final app = await _openApp(_settingsRead);

      await _seedAccount(app, 'Alice');
      await app.database
          .into(app.database.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'home:activated:$_userId',
              valueBool: const Value(true),
            ),
          );
      app.poison.arm();

      expect(await app.home.isActivated(userId: _userId), isTrue);
      expect(await _displayNames(app), ['Alice']);
      expect(await _userVersion(app.database), 5);
      expect(app.poison.fired, isTrue);
    });
  });
}

bool _homeActivationWrite(String sql) =>
    sql.contains('INSERT OR REPLACE') && sql.contains('"settings"');

bool _accountList(String sql) =>
    sql.contains('FROM "accounts"') && !sql.contains('WHERE');

bool _accountUpdate(String sql) => sql.contains('UPDATE "accounts"');

bool _settingsRead(String sql) =>
    sql.contains('FROM "settings"') && sql.contains('WHERE');

Future<void> _seedAccount(_App app, String displayName) => app.database
    .into(app.database.accounts)
    .insert(
      AccountsCompanion.insert(
        id: _accountId,
        displayName: Value(displayName),
      ),
    );

Future<List<String>> _displayNames(_App app) async {
  final accounts = await app.auth.getAccountsAll();
  return [for (final account in accounts) account.displayName];
}

Future<int> _userVersion(Database database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.data.values.single! as int;
}

class _App {
  _App(this.database, this.auth, this.home, this.poison);

  final Database database;
  final AuthLocalRepository auth;
  final HomeOrientationPreferencesRepository home;
  final _Poison poison;
}

Future<_App> _openApp(bool Function(String sql) matches) async {
  final poison = _Poison(matches);
  final directory = Directory.systemTemp.createTempSync('tentura-local-db-');
  final file = File('${directory.path}/main.sqlite');
  final database = Database(
    const Env(),
    Logger('test'),
    ReopeningQueryExecutor(
      () => NativeDatabase(file).interceptWith(_LogicErrorOnce(poison)),
      retryDelays: const [Duration.zero],
      delay: (_) async {},
    ),
  );
  addTearDown(database.close);
  addTearDown(() => directory.deleteSync(recursive: true));
  return _App(
    database,
    AuthLocalRepository(Logger('test'), database, LocalSecureStorage()),
    HomeOrientationPreferencesRepository(database),
    poison,
  );
}

/// Fails the next matching statement once, the way the web worker does:
/// SqliteException(1) whose own text is only "SQL logic error".
final class _Poison {
  _Poison(this._matches);

  final bool Function(String sql) _matches;

  var _armed = false;
  bool fired = false;

  void arm() => _armed = true;

  void consider(String sql) {
    if (!_armed || fired || !_matches(sql)) {
      return;
    }
    fired = true;
    throw SqliteException(
      extendedResultCode: 1,
      message: _logicError,
      explanation: '$_logicError (code 1)',
      operation: 'executing statement',
      causingStatement: sql,
    );
  }
}

final class _LogicErrorOnce extends QueryInterceptor {
  _LogicErrorOnce(this._poison);

  final _Poison _poison;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _poison.consider(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _poison.consider(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _poison.consider(statement);
    return super.runSelect(executor, statement, args);
  }
}
