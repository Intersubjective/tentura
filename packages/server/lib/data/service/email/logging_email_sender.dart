import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';

/// Test-environment sender: logs instead of calling Resend.
@Singleton(as: EmailSenderPort, env: [Environment.test], order: 1)
class LoggingEmailSender implements EmailSenderPort {
  static final _log = Logger('LoggingEmailSender');

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    _log.info('magic link to=$to inviter=$inviterName url=$verifyUrl');
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    _log.info(
      'notification email to=$to locale=$locale title=${content.item.title}',
    );
  }

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    _log.info(
      'digest email to=$to locale=$locale items=${content.totalItems}',
    );
  }
}
