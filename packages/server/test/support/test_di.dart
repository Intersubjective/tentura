import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/env.dart';

import 'test_di.config.dart';

export 'package:tentura_server/app/di.dart' show getIt;

@InjectableInit(
  generateForDir: ['test/support/mocks'],
  initializerName: 'initTestMocks',
  preferRelativeImports: true,
)
Future<GetIt> configureTestDependencies(Env env) async {
  // The application initializer constructs singletons that use these ports.
  getIt.initTestMocks(environment: env.environment);
  return configureDependencies(env);
}
