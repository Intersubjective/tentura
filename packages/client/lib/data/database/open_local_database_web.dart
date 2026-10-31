import 'dart:js_interop';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web/web.dart' as web;

DatabaseConnection Function() localDatabaseOpener(
  String name, {
  required Future<void> Function(QueryExecutor) restoreAccounts,
}) => _WebDatabaseOpener(name, restoreAccounts).call;

final _logger = Logger('LocalDatabase');

final class _WebDatabaseOpener {
  _WebDatabaseOpener(this.name, this.restoreAccounts);

  final String name;
  final Future<void> Function(QueryExecutor) restoreAccounts;
  bool skipImport = false;
  bool _reportedStorage = false;

  DatabaseConnection call() {
    final attempt = _WebOpenAttempt(this);
    return DatabaseConnection(LazyDatabase(attempt.connect)).interceptWith(
      attempt,
    );
  }

  Future<void> reportStorage(WasmStorageImplementation storage) async {
    if (_reportedStorage) return;
    _reportedStorage = true;
    _logger.info('Local database storage: ${storage.name}');
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'local_db',
        message: 'local_db:storage_selected',
        data: {'implementation': storage.name},
      ),
    );
  }
}

final class _WebOpenAttempt extends QueryInterceptor {
  _WebOpenAttempt(this.opener);

  final _WebDatabaseOpener opener;
  late WasmProbeResult _probe;
  bool _hasLegacy = false;
  bool _imported = false;
  bool _initialized = false;

  ExistingDatabase get _legacy => (WebStorageApi.opfs, opener.name);
  ExistingDatabase get _indexedDb => (WebStorageApi.indexedDb, opener.name);

  Future<QueryExecutor> connect() async {
    _probe = await WasmDatabase.probe(
      databaseName: opener.name,
      sqlite3Uri: Uri.parse('/assets/packages/sqlite3.wasm'),
      driftWorkerUri: Uri.parse('/assets/packages/drift_worker.js'),
    );
    final storage =
        _probe.availableStorages.contains(
          WasmStorageImplementation.sharedIndexedDb,
        )
        ? WasmStorageImplementation.sharedIndexedDb
        : WasmStorageImplementation.unsafeIndexedDb;
    if (!_probe.availableStorages.contains(storage)) {
      throw StateError('IndexedDB is unavailable for the local database');
    }
    await opener.reportStorage(storage);

    _hasLegacy = _probe.existingDatabases.contains(_legacy);
    return _probe.open(
      storage,
      opener.name,
      // Drift calls this only if the SQLite file is absent. An IndexedDB
      // container alone can survive a crash before the import was persisted.
      initializeDatabase: _hasLegacy && !opener.skipImport
          ? _importLegacy
          : null,
    );
  }

  Future<Uint8List?> _importLegacy() async {
    try {
      final bytes = await _probe.exportDatabase(_legacy);
      _imported = bytes != null;
      if (bytes == null) opener.skipImport = true;
      return bytes;
    } catch (error, stack) {
      opener.skipImport = true;
      _logger.warning(
        'Local database import failed (${error.runtimeType}); rebuilding accounts from secure storage',
        null,
        stack,
      );
      return null;
    }
  }

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    if (_initialized) return executor.ensureOpen(user);
    // The shared worker owns SQL writes. This lock also serializes the one-time
    // probe/import/cleanup across tabs, including failed or interrupted opens.
    final result = await web.window.navigator.locks
        .request(
          'tentura:local-db:${opener.name}',
          ((web.Lock? lock) => _ensureOpen(
            executor,
            user,
          ).then((opened) => opened.toJS).toJS).toJS,
        )
        .toDart;
    return result.dartify() == true;
  }

  Future<bool> _ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    bool opened;
    try {
      opened = await executor.ensureOpen(
        _RecoverSeedAccountsUser(user, opener),
      );
    } catch (error, stack) {
      if (_imported) {
        // An unreadable imported SQLite file must not become a sticky failure.
        // Keep OPFS until a replacement really opens, and let the existing
        // reopening executor open an empty IndexedDB database next time.
        opener.skipImport = true;
        await executor.close();
        await _probe.deleteDatabase(_indexedDb);
        _logger.warning(
          'Local database import could not open (${error.runtimeType}); rebuilding accounts from secure storage',
          null,
          stack,
        );
      }
      rethrow;
    }
    if (_hasLegacy) {
      await _probe.deleteDatabase(_legacy);
      _hasLegacy = false;
    }
    _initialized = true;
    return opened;
  }
}

final class _RecoverSeedAccountsUser extends QueryExecutorUser {
  _RecoverSeedAccountsUser(this.user, this.opener);

  final QueryExecutorUser user;
  final _WebDatabaseOpener opener;

  @override
  int get schemaVersion => user.schemaVersion;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {
    await user.beforeOpen(executor, details);
    if (opener.skipImport) await opener.restoreAccounts(executor);
  }
}
