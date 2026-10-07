import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import '../data/database/tentura_db.dart';
import '../env.dart';

@module
abstract class RegisterModule {
  @Named('auth')
  @Singleton(env: [Environment.dev, Environment.prod])
  TenturaDb authDatabase(Env env) => TenturaDb(env);

  @singleton
  Logger get logger => Logger.root;

  @singleton
  Random get random => Random.secure();
}
