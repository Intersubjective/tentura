import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import '../../env.dart';
import 'di.config.dart';

@InjectableInit()
Future<GetIt> configureDependencies() async {
  await BlurHash.loadShader();
  const envName = String.fromEnvironment('ENV', defaultValue: 'dev');
  final injectableEnv = switch (envName) {
    'test' => Environment.test,
    'prod' => Environment.prod,
    _ => Environment.dev,
  };
  final getIt = await GetIt.I.init(environment: injectableEnv);
  final env = getIt<Env>();

  Logger.root.level = Level.LEVELS.firstWhere(
    (e) => e.name == env.logLevel,
    orElse: () => kDebugMode ? Level.INFO : Level.ALL,
  );

  if (kDebugMode) {
    Logger.root.onRecord.listen(
      // ignore: avoid_print //
      (e) => print('${e.level.name}: ${e.message}'),
    );
  }

  return getIt;
}
