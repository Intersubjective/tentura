import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web/web.dart' as web;

import 'reopening_query_executor.dart';

/// How long one request for the cross-tab database lock waits (#1123).
/// Another tab holds it only while it opens the database, normally well under
/// a second; a tab frozen mid-open holds it forever.
const kLocalDatabaseLockWait = Duration(seconds: 8);

/// How many times the lock is requested before the open fails with
/// [LocalDatabaseLockHeldException]: in all well within the 60 s boot timeout.
const kLocalDatabaseLockAttempts = 3;

DatabaseConnection Function() localDatabaseOpener(
  String name, {
  required Future<void> Function(QueryExecutor) restoreAccounts,
  Duration lockWait = kLocalDatabaseLockWait,
  int lockAttempts = kLocalDatabaseLockAttempts,
}) => _WebDatabaseOpener(
  name,
  restoreAccounts,
  lockWait: lockWait,
  lockAttempts: lockAttempts,
).call;

final _logger = Logger('LocalDatabase');

final class _WebDatabaseOpener {
  _WebDatabaseOpener(
    this.name,
    this.restoreAccounts, {
    required this.lockWait,
    required this.lockAttempts,
  });

  final String name;
  final Future<void> Function(QueryExecutor) restoreAccounts;
  final Duration lockWait;
  final int lockAttempts;
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
    await _breadcrumb('storage_selected', {'implementation': storage.name});
  }
}

/// One breadcrumb per stage of the open (#1123): when boot hangs, the last
/// one in the Sentry report names the stage that never finished.
Future<void> _breadcrumb(String stage, [Map<String, Object>? data]) =>
    Sentry.addBreadcrumb(
      Breadcrumb(category: 'local_db', message: 'local_db:$stage', data: data),
    );

final class _WebOpenAttempt extends QueryInterceptor {
  _WebOpenAttempt(this.opener);

  final _WebDatabaseOpener opener;
  late WasmProbeResult _probe;
  bool _hasLegacy = false;
  bool _imported = false;
  bool _initialized = false;

  ExistingDatabase get _legacy => (WebStorageApi.opfs, opener.name);
  ExistingDatabase get _indexedDb => (WebStorageApi.indexedDb, opener.name);

  /// Probes once per open attempt, before the lock: read-only, and its own
  /// breadcrumbs tell a stalled probe apart from a held lock (#1123).
  late final Future<void> _probed = _runProbe();

  Future<void> _runProbe() async {
    await _breadcrumb('probe_started');
    _probe = await WasmDatabase.probe(
      databaseName: opener.name,
      sqlite3Uri: Uri.parse(web.document.baseURI).resolve(
        ui_web.assetManager.getAssetUrl('packages/sqlite3.wasm'),
      ),
      driftWorkerUri: Uri.parse(web.document.baseURI).resolve(
        ui_web.assetManager.getAssetUrl('packages/drift_worker.js'),
      ),
    );
    await _breadcrumb('probe_finished');
  }

  /// Runs inside the lock, after [_probed].
  Future<QueryExecutor> connect() async {
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
      await _breadcrumb('import_started');
      final bytes = await _probe.exportDatabase(_legacy);
      _imported = bytes != null;
      if (bytes == null) opener.skipImport = true;
      await _breadcrumb('import_finished', {'imported': _imported});
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
    await _probed;
    // The shared worker owns SQL writes. This lock also serializes the one-time
    // import/cleanup across tabs, including failed or interrupted opens. A
    // probe result can be stale by the time the lock is granted: a legacy
    // database another tab imported meanwhile is not imported again (the
    // SQLite file exists), and deleting it again is a no-op.
    // A tab frozen in the middle of its open keeps the lock forever, so each
    // request waits a bounded time and the open fails after the last one
    // instead of hanging boot until its timeout (#1123).
    final lockName = 'tentura:local-db:${opener.name}';
    final waited = Stopwatch()..start();
    for (var attempt = 1; attempt <= opener.lockAttempts; attempt++) {
      await _breadcrumb('lock_wait_started', {'attempt': attempt});
      final timeout = web.AbortSignal.timeout(
        opener.lockWait.inMilliseconds,
      );
      var granted = false;
      try {
        final result = await web.window.navigator.locks
            .request(
              lockName,
              web.LockOptions(signal: timeout),
              ((web.Lock? lock) {
                granted = true;
                return _ensureOpenLocked(
                  executor,
                  user,
                  waited.elapsedMilliseconds,
                ).then((opened) => opened.toJS).toJS;
              }).toJS,
            )
            .toDart;
        return result.dartify() == true;
      } on Object {
        // Only a request still waiting when its time ran out is retried.
        if (granted || !timeout.aborted) rethrow;
      }
    }
    throw LocalDatabaseLockHeldException(
      lockName: lockName,
      attempts: opener.lockAttempts,
      waitPerAttempt: opener.lockWait,
    );
  }

  Future<bool> _ensureOpenLocked(
    QueryExecutor executor,
    QueryExecutorUser user,
    int waitMs,
  ) async {
    await _breadcrumb('lock_acquired', {'wait_ms': waitMs});
    final opened = await _ensureOpen(executor, user);
    await _breadcrumb('open_finished');
    return opened;
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
