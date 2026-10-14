import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/env.dart';

import '../service/main_db_scope_admission.dart';

/// Owns the main connection budget; database handles do not own another pool.
@lazySingleton
final class MainDbPool {
  @factoryMethod
  MainDbPool(Env env) : this._(env, env.pgPoolSettings);

  MainDbPool.auth(Env env)
    : this._(
        env,
        PoolSettings(
          maxConnectionCount: 1,
          maxConnectionAge: env.pgPoolSettings.maxConnectionAge,
          maxSessionUse: env.pgPoolSettings.maxSessionUse,
          connectTimeout: env.pgPoolSettings.connectTimeout,
          sslMode: env.pgPoolSettings.sslMode,
          onOpen: env.pgPoolSettings.onOpen,
        ),
      );

  MainDbPool._(Env env, PoolSettings settings)
    : _endpoint = env.pgEndpoint,
      _controlSettings = env.pgEndpointSettings,
      statementTimeout = Duration(milliseconds: env.pgStatementTimeoutMs),
      logStatements = env.isDebugModeOn,
      enforceGuards = env.isDebugModeOn || env.environment == Environment.test,
      pool = Pool<dynamic>.withEndpoints(
        [env.pgEndpoint],
        settings: settings,
      ),
      admission = MainDbScopeAdmission(
        maxConcurrent: settings.maxConnectionCount ?? 4,
        enforceReentryGuard:
            env.isDebugModeOn || env.environment == Environment.test,
      );

  final bool logStatements;

  /// Ownership/re-entry guards: on in test and debug, off in production.
  final bool enforceGuards;
  final Pool<dynamic> pool;
  final MainDbScopeAdmission admission;
  final Duration statementTimeout;
  final Endpoint _endpoint;
  final ConnectionSettings _controlSettings;
  Connection? _control;
  Future<void> _controlTail = Future.value();

  /// Never queue cancellation on the occupied application pool. The lease
  /// remains held until this control command has completed.
  Future<void> cancelBackend(int pid, bool Function() stillOwnsBackend) {
    final result = _controlTail.then((_) async {
      if (!stillOwnsBackend()) return;
      var control = _control;
      if (control == null || !control.isOpen) {
        control = await Connection.open(_endpoint, settings: _controlSettings);
        _control = control;
      }
      if (!stillOwnsBackend()) return;
      await control.execute(
        Sql.named('''
          SELECT pg_cancel_backend(@pid)
          WHERE EXISTS (
            SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database() AND pid = @pid
          )
        '''),
        parameters: {'pid': pid},
        timeout: const Duration(seconds: 2),
      );
    });
    _controlTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @disposeMethod
  Future<void> close() async {
    admission.close();
    await pool.close();
    await _controlTail;
    await _control?.close();
  }
}
