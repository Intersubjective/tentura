import 'dart:async';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_drift/sentry_drift.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:tentura/data/database/reopening_query_executor.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/like/domain/port/like_write_port.dart';

@module
abstract class RegisterModule {
  @singleton
  LikeWritePort likeWritePort(LikeRemoteRepository repository) => repository;

  @singleton
  AuthRemoteClient authRemoteClient(RemoteApiService service) => service;

  /// The narrow capability Settings **Reset counters** needs (D15). Same
  /// instance as [AttentionCase] — §0.3's single attention owner is not
  /// duplicated, only viewed through a smaller opening.
  @singleton
  AttentionReconcilePort attentionReconcilePort(AttentionCase attention) =>
      attention;

  @singleton
  BeaconWritePort beaconWritePort(BeaconRepository repository) => repository;

  @singleton
  BeaconImagePort beaconImagePort(ImageRepository repository) => repository;

  @singleton
  RemoteRequestClient remoteRequestClient(RemoteApiService service) => service;

  @singleton
  RemoteApiClient remoteApiClient(RemoteApiService service) => service;

  @singleton
  NetworkReachabilityPort networkReachabilityPort(
    NetworkReachability reachability,
  ) => reachability;

  @singleton
  Logger get logger => Logger.root;

  /// The local database. A failed open is retried on a fresh connection
  /// (web: the previous page may still hold the OPFS file, #674).
  @singleton
  QueryExecutor get database {
    DatabaseConnection open() => driftDatabase(
      name: _mainDbName,
      native: const DriftNativeOptions(shareAcrossIsolates: true),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('/assets/packages/sqlite3.wasm'),
        driftWorker: Uri.parse('/assets/packages/drift_worker.js'),
      ),
    );
    final initial = open();
    return DatabaseConnection(
      ReopeningQueryExecutor(
        open,
        initial: initial,
        onRetry: _reportDatabaseReopen,
      ),
      // Keep drift's store: on the web it relays table updates across tabs.
      streamQueries: initial.streamQueries,
    ).interceptWith(SentryQueryInterceptor(databaseName: _mainDbName));
  }

  static void _reportDatabaseReopen(
    int attempt,
    Object error,
    StackTrace stackTrace,
  ) {
    _databaseLogger.warning(
      'Opening the local database failed (attempt $attempt), reopening',
      error,
      stackTrace,
    );
    // The Logger → Sentry bridge is installed only after DI is configured,
    // so leave the breadcrumb directly.
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'local_db',
          level: SentryLevel.warning,
          message: 'local_db:open_failed',
          data: {'attempt': attempt, 'error': error.toString()},
        ),
      ),
    );
  }

  static final _databaseLogger = Logger('LocalDatabase');

  static const _mainDbName = 'main_db';
}
