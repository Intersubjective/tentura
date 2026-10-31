// Test-only entry point for scripts/e2e_local_database/suite.mjs. Compile with
// flutter build web --wasm: the production DI getter, worker, wasm and browser
// storage APIs are used without replacing the executor or secure storage.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/wasm.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/di/modules.dart';
import 'package:tentura/data/database/database.dart';
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/contacts/data/repository/contacts_repository.dart';
import 'package:tentura/features/settings/data/repository/settings_repository.dart';

final class _Module extends RegisterModule {}

final class _DiscardTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      envelope.header.eventId;
}

final _logger = Logger('LocalDatabaseBrowserTest');
final _storage = LocalSecureStorage();
final _logs = <String>[];
final _breadcrumbs = <Map<String, dynamic>>[];
Database? _database;
AuthLocalRepository? _accounts;
late SettingsRepository _settings;
late ContactsRepository _contacts;
RemoteApiService? _remote;

// Seeds are real 32-byte base64 values, persisted by AuthLocalRepository in
// FlutterSecureStorage, rather than by a fake secure-storage platform.
final _seedAccounts = [
  {
    'id': 'Uowner0000001',
    'displayName': 'Owner / Владелец',
    'seed': base64Encode(List<int>.generate(32, (i) => i)),
  },
  {
    'id': 'Utester000001',
    'displayName': 'QA / Проверка',
    'seed': base64Encode(List<int>.generate(32, (i) => 255 - i)),
  },
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) => _logs.add(record.message));
  await Sentry.init((options) {
    options
      ..dsn = 'https://public@example.invalid/1'
      ..transport = _DiscardTransport()
      ..beforeBreadcrumb = (breadcrumb, hint) {
        if (breadcrumb != null) _breadcrumbs.add(breadcrumb.toJson());
        return breadcrumb;
      };
  });
  globalContext['localDatabaseCall'] = ((JSString request) => _call(
    request.toDart,
  ).then((response) => response.toJS).toJS).toJS;
}

Future<String> _call(String request) async {
  final input = jsonDecode(request) as Map<String, dynamic>;
  try {
    return jsonEncode({'ok': true, 'value': await _dispatch(input)});
  } catch (error, stack) {
    return jsonEncode({
      'ok': false,
      'error': error.toString(),
      'stack': stack.toString(),
    });
  }
}

Future<Object?> _dispatch(Map<String, dynamic> input) async {
  switch (input['operation']) {
    case 'open':
    case 'legacy':
      QueryExecutor executor;
      if (input['operation'] == 'legacy') {
        // Fixture only: faithfully create the pre-switch OPFS database with
        // the shipped assets and the current application schema.
        final probe = await _probe();
        if (!probe.availableStorages.contains(
          WasmStorageImplementation.opfsLocks,
        )) {
          throw StateError(
            'OPFS fixture requires cross-origin isolated Chrome',
          );
        }
        executor = await probe.open(
          WasmStorageImplementation.opfsLocks,
          'main_db',
        );
      } else {
        executor = _Module().database;
      }
      final database = _database = Database(const Env(), _logger, executor);
      _accounts = AuthLocalRepository(_logger, database, _storage);
      _settings = SettingsRepository(database);
      _remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      _contacts = ContactsRepository(_remote!, database);
      // Force the lazy production open now, not when inspecting its storage.
      await _accounts!.getAccountsAll();
      return true;
    case 'seed':
      for (final account in _seedAccounts) {
        await _accounts!.addAccount(
          account['id']!,
          account['seed']!,
          account['displayName'],
        );
      }
      await _accounts!.setCurrentAccountId(_seedAccounts.first['id']);
      await _settings.setThemeMode('dark');
      await _settings.setLocalePreference('ru');
      await _settings.setIsIntroEnabled(false);
      return _seedAccounts;
    case 'snapshot':
      return {
        'accounts': [
          for (final account in await _accounts!.getAccountsAll())
            {'id': account.id, 'displayName': account.displayName},
        ],
        'currentAccountId': await _accounts!.getCurrentAccountId(),
        'theme': await _settings.getThemeModeName(),
        'locale': await _settings.getLocalePreference(),
        'intro': await _settings.getIsIntroEnabled(),
      };
    case 'seeds':
      return {
        for (final account in _seedAccounts)
          account['id']!: await _storage.read('Auth:Id:${account['id']}'),
      };
    case 'contacts':
      final round = input['round'] as int;
      await _contacts.replaceCache(
        accountId: _seedAccounts.first['id']!,
        names: {
          for (var i = 0; i < 50; i++)
            'subject-$i': 'round-$round-contact-$i-${'name' * 20}',
        },
      );
      return true;
    case 'readContacts':
      return _contacts.getCached(accountId: _seedAccounts.first['id']!);
    case 'settingsAndAccounts':
      final round = input['round'] as int;
      await _settings.setAppId('round-$round');
      await _settings.setIsIntroEnabled(round.isEven);
      final account = await _accounts!.getAccountById(
        _seedAccounts.first['id']!,
      );
      if (account == null) throw StateError('The owner account disappeared');
      await _accounts!.updateAccount(
        account.copyWith(displayName: 'Owner $round'),
      );
      return {
        'appId': await _settings.getAppId(),
        'accounts': (await _accounts!.getAccountsAll()).length,
      };
    case 'readAppId':
      return _settings.getAppId();
    case 'roundState':
      return {
        'contacts': await _contacts.getCached(
          accountId: _seedAccounts.first['id']!,
        ),
        'appId': await _settings.getAppId(),
        'intro': await _settings.getIsIntroEnabled(),
        'accounts': [
          for (final account in await _accounts!.getAccountsAll())
            {'id': account.id, 'displayName': account.displayName},
        ],
      };
    case 'inventory':
      final probe = await _probe();
      return {
        'available': [for (final mode in probe.availableStorages) mode.name],
        'existing': [
          for (final (api, name) in probe.existingDatabases)
            {'api': api.name, 'name': name},
        ],
      };
    case 'telemetry':
      return {'logs': _logs, 'breadcrumbs': _breadcrumbs};
    case 'close':
      await _accounts?.dispose();
      await _database?.close();
      await _remote?.close();
      return true;
    default:
      throw ArgumentError.value(input['operation'], 'operation');
  }
}

Future<WasmProbeResult> _probe() => WasmDatabase.probe(
  databaseName: 'main_db',
  sqlite3Uri: Uri.parse('/assets/packages/sqlite3.wasm'),
  driftWorkerUri: Uri.parse('/assets/packages/drift_worker.js'),
);
