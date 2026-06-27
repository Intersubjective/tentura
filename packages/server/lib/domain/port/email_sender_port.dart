import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
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

  /// Notifies the admin inbox that a profile-deletion request was submitted.
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  });

  /// Confirms to the user that their profile-deletion request was recorded.
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  });
}
