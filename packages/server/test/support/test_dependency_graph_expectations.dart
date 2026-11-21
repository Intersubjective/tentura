import 'package:test/test.dart';
import 'package:tentura_server/data/service/email/logging_email_sender.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/env.dart';

import 'mocks/user_trust_edge_repository_mock.dart';
import 'test_di.dart';

Future<void> expectTestDependencyGraph(Env env) async {
  await configureTestDependencies(env);

  expect(getIt<Env>(), same(env));
  expect(
    getIt<UserTrustEdgeRepositoryPort>(),
    isA<UserTrustEdgeRepositoryMock>(),
  );
  expect(getIt<EmailSenderPort>(), isA<LoggingEmailSender>());
  expect(getIt<UserTrustEdgeCase>(), isA<UserTrustEdgeCase>());
  await getIt.getAsync<PgNotificationService>();
}
