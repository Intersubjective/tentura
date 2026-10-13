import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../data/database/tentura_db.dart';
import '../env.dart';

/// Closes the dedicated auth database when the DI container is disposed.
Future<void> disposeAuthDatabase(TenturaDb database) => database.close();

@module
abstract class RegisterModule {
  @Named('auth')
  @Singleton(
    env: [Environment.dev, Environment.prod],
    dispose: disposeAuthDatabase,
  )
  TenturaDb authDatabase(Env env) => TenturaDb.auth(env);

  @singleton
  Logger get logger => Logger.root;

  @singleton
  Random get random => Random.secure();
}
