import 'package:injectable/injectable.dart';

import 'package:tentura/data/repository/remote_repository.dart';

import 'package:tentura/features/settings/data/gql/_g/email_send_test.req.gql.dart';
import 'package:tentura/features/settings/domain/entity/email_test_send_result.dart';
import 'package:tentura/features/settings/domain/port/email_test_remote_repository_port.dart';

@Singleton(
  as: EmailTestRemoteRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class EmailTestRemoteRepository extends RemoteRepository
    implements EmailTestRemoteRepositoryPort {
  EmailTestRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  @override
  Future<EmailTestSendResult> sendTestEmail() async {
    final data = await requestDataOnlineOrThrow(
      GEmailSendTestReq(),
      label: _label,
    );
    final result = data.emailSendTest;
    return EmailTestSendResult(
      ok: result.ok,
      mock: result.mock,
      reason: result.reason,
    );
  }

  static const _label = 'EmailTest';
}
