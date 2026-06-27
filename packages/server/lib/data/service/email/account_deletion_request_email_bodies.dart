import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';

/// Subject/html/text for account-deletion request emails (Resend + file sink).
abstract final class AccountDeletionRequestEmailBodies {
  static String escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static ({String subject, String html, String text}) admin(
    AccountDeletionRequestEmailPayload payload,
  ) {
    final id = escapeHtml(payload.complaintId);
    final userId = escapeHtml(payload.userId);
    final contact = escapeHtml(payload.contactEmail);
    final details = escapeHtml(payload.details);
    final at = payload.requestedAt.toUtc().toIso8601String();
    final html =
        '''
<p>A user submitted a profile deletion request on Tentura.</p>
<ul>
<li>Complaint id: $id</li>
<li>User id: $userId</li>
<li>Contact email: $contact</li>
<li>Requested at (UTC): $at</li>
</ul>
<p>Details:</p>
<p>$details</p>
''';
    final text =
        'Profile deletion request\n'
        'Complaint id: ${payload.complaintId}\n'
        'User id: ${payload.userId}\n'
        'Contact email: ${payload.contactEmail}\n'
        'Requested at (UTC): $at\n\n'
        'Details:\n${payload.details}';
    return (
      subject: 'Tentura profile deletion request',
      html: html,
      text: text,
    );
  }

  static ({String subject, String html, String text}) userConfirmation(
    AccountDeletionRequestEmailPayload payload,
  ) {
    const html =
        '''
<p>We received your Tentura profile deletion request.</p>
<p>Your request has been recorded and an administrator has been notified. They will review it and remove your profile and data after approval.</p>
<p>If you did not submit this request, you can ignore this email.</p>
''';
    const text =
        'We received your Tentura profile deletion request.\n\n'
        'Your request has been recorded and an administrator has been notified. '
        'They will review it and remove your profile and data after approval.\n\n'
        'If you did not submit this request, you can ignore this email.';
    return (
      subject: 'Your Tentura profile deletion request was received',
      html: html,
      text: text,
    );
  }
}
