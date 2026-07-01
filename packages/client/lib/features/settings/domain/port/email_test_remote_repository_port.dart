import '../entity/email_test_send_result.dart';

abstract class EmailTestRemoteRepositoryPort {
  Future<EmailTestSendResult> sendTestEmail();
}
