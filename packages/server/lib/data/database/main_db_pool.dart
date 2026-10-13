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
    : logStatements = env.isDebugModeOn,
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

  @disposeMethod
  Future<void> close() async {
    admission.close();
    await pool.close();
  }
}
