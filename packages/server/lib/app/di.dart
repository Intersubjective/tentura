import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../env.dart';
import '../domain/port/attention_ack_port.dart';
import '../domain/port/attention_query_port.dart';
import 'di.config.dart';

final getIt = GetIt.instance;

// Injectable 3.1 compares optional nullable constructor parameters against
// non-null registrations with nullability intact, then reports false missing-
// dependency warnings even though it emits the correct `gh<T>()` wiring. The
// type-based ignore has the same nullability bug, so scope the workaround to
// these two exact source imports.
@InjectableInit(
  ignoreUnregisteredTypes: [Env, AttentionAckPort, AttentionQueryPort],
  ignoreUnregisteredTypesInPackages: [
    'tentura_server/domain/use_case/attention_intent_case.dart',
    'tentura_server/domain/use_case/transactional_attention_case.dart',
    'tentura_server/domain/use_case/attention_expiry_sweep_case.dart',
    'tentura_server/domain/use_case/notification_center_case.dart',
    'tentura_server/domain/port/attention_query_port.dart',
    'tentura_server/domain/port/attention_ack_port.dart',
  ],
)
Future<GetIt> configureDependencies(Env env) async {
  getIt.registerSingleton(env);
  return getIt.init(environment: env.environment);
}
