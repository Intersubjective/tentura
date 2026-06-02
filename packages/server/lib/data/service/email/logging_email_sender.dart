import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';

/// Test-environment sender: logs the verify URL instead of calling Resend.
@Singleton(as: EmailSenderPort, env: [Environment.test], order: 1)
class LoggingEmailSender implements EmailSenderPort {
  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    Logger('LoggingEmailSender').info(
      'magic link to=$to inviter=$inviterName url=$verifyUrl',
    );
  }
}
