import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_drift/sentry_drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';

@module
abstract class RegisterModule {
  @singleton
  AuthRemoteClient authRemoteClient(RemoteApiService service) => service;

  @singleton
  Logger get logger => Logger.root;

  @singleton
  QueryExecutor get database => driftDatabase(
    name: _mainDbName,
    native: const DriftNativeOptions(shareAcrossIsolates: true),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('/assets/packages/sqlite3.wasm'),
      driftWorker: Uri.parse('/assets/packages/drift_worker.js'),
    ),
  ).interceptWith(SentryQueryInterceptor(databaseName: _mainDbName));

  static const _mainDbName = 'main_db';
}
