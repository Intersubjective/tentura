import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_drift/sentry_drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

@module
abstract class RegisterModule {
  @singleton
  Logger get logger => Logger();

  @singleton
  SentryNavigatorObserver get sentryNavigatorObserver =>
      SentryNavigatorObserver();

  @singleton
  // ignore: deprecated_member_use // TBD: change after 9.0.0
  QueryExecutor get database => SentryQueryExecutor(
    () => driftDatabase(
      name: 'main_db',
      native: const DriftNativeOptions(shareAcrossIsolates: true),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('/assets/packages/sqlite3.wasm'),
        driftWorker: Uri.parse('/assets/packages/drift_worker.js'),
      ),
    ),
    databaseName: 'main_db',
  );
}
