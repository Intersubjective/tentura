import 'dart:async';

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';
import 'package:sentry_drift/sentry_drift.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/data/database/open_local_database.dart'
    if (dart.library.js_interop) 'package:tentura/data/database/open_local_database_web.dart';

import 'package:tentura/data/database/reopening_query_executor.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_client/auth_remote_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/like/domain/port/like_write_port.dart';
import 'package:tentura/features/like/domain/port/person_trust_writes_port.dart';

@module
abstract class RegisterModule {
  @singleton
  LikeWritePort likeWritePort(LikeRemoteRepository repository) => repository;

  @singleton
  PersonTrustWritesPort personTrustWritesPort(
    LikeRemoteRepository repository,
  ) => repository;

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

  /// The local database. A failed open is retried on a fresh connection.
  @singleton
  QueryExecutor get database {
    final open = localDatabaseOpener(
      _mainDbName,
      restoreAccounts: AuthLocalRepository.restoreSeedAccounts,
    );
    // A plain, connection-independent stream store on purpose: drift's
    // per-connection stores (cross-tab / cross-isolate relays) stay bound to
    // the connection that made them, which a reopen abandons. Nothing here
    // watches local tables, so nothing needs cross-tab updates; a future
    // `.watch()` still updates for writes made by this tab.
    return DatabaseConnection(
      ReopeningQueryExecutor(
        open,
        onRetry: _reportDatabaseReopen,
        onStatementError: _reportDatabaseStatementError,
      ),
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

  /// Which statement failed, and in which state of the database, for the
  /// SQLite errors seen in long web sessions (#703). The SQL, the error's
  /// type and result code only — never its text, which carries the
  /// statement's arguments.
  static void _reportDatabaseStatementError(DatabaseStatementFailure failure) =>
      logDatabaseStatementFailure(_databaseLogger, failure);

  static final _databaseLogger = Logger('LocalDatabase');

  static const _mainDbName = 'main_db';
}
