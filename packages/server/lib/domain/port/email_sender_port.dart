import 'package:tentura_server/domain/entity/email_notification_content.dart';

/// Outbound email (implementation owns transport + markup).
abstract class EmailSenderPort {
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  });

  /// A single high-stakes "asked of you" notification email.
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  });

  /// The batched digest of pending items.
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  });
}
