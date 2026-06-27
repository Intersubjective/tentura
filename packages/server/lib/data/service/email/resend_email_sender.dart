import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:tentura_server/data/service/email/account_deletion_request_email_bodies.dart';
import 'package:tentura_server/data/service/email/file_sink_email_sender.dart' show FileSinkEmailSender;
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';

import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// Production sender via the Resend API. Registered through
/// `EmailSenderModule` (dev/prod), which swaps in [FileSinkEmailSender] when
/// `EMAIL_DEBUG_SINK_DIR` is set.
class ResendEmailSender implements EmailSenderPort {
  ResendEmailSender(this._env) : _client = http.Client();

  final Env _env;
  final http.Client _client;

  static const _renderer = EmailTemplateRenderer();

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    final r = _renderer.renderNotification(content: content, locale: locale);
    await _post(
      to: to,
      subject: r.subject,
      html: r.html,
      text: r.text,
      listUnsubscribeUrl: listUnsubscribeUrl,
    );
  }

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    final r = _renderer.renderDigest(content: content, locale: locale);
    await _post(
      to: to,
      subject: r.subject,
      html: r.html,
      text: r.text,
      listUnsubscribeUrl: listUnsubscribeUrl,
    );
  }

  Future<void> _post({
    required String to,
    required String subject,
    required String html,
    required String text,
    String? listUnsubscribeUrl,
  }) async {
    if (!_env.isEmailAuthConfigured) {
      throw StateError('Resend is not configured');
    }
    final headers = {
      'Authorization': 'Bearer ${_env.resendApiKey}',
      'Content-Type': 'application/json',
    };
    final body = <String, dynamic>{
      'from': _env.resendFromEmail,
      'to': [to],
      'subject': subject,
      'html': html,
      'text': text,
    };
    if (listUnsubscribeUrl != null && listUnsubscribeUrl.isNotEmpty) {
      body['headers'] = {
        'List-Unsubscribe': '<$listUnsubscribeUrl>',
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
      };
    }
    final response = await _client.post(
      Uri.parse('https://api.resend.com/emails'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Logger('ResendEmailSender').warning(
        'Resend API ${response.statusCode}: ${response.body}',
      );
      throw StateError('Failed to send email');
    }
  }

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    if (!_env.isEmailAuthConfigured) {
      throw StateError('Resend is not configured');
    }
    final inviterLine = inviterName != null && inviterName.trim().isNotEmpty
        ? '<p>${_escapeHtml(inviterName.trim())} invited you to Tentura.</p>'
        : '';
    final html =
        '''
<p>Sign in to Tentura using this link (valid for a short time, one use only):</p>
$inviterLine
<p><a href="${_escapeHtml(verifyUrl)}">Continue to Tentura</a></p>
<p>If you did not request this, you can ignore this email.</p>
''';
    final text =
        'Sign in to Tentura: $verifyUrl\n\n'
        'This link is valid for a short time and works once. '
        'If you did not request this, ignore this email.';

    final response = await _client.post(
      Uri.parse('https://api.resend.com/emails'),
      headers: {
        'Authorization': 'Bearer ${_env.resendApiKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'from': _env.resendFromEmail,
        'to': [to],
        'subject': 'Sign in to Tentura',
        'html': html,
        'text': text,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Logger('ResendEmailSender').warning(
        'Resend API ${response.statusCode}: ${response.body}',
      );
      throw StateError('Failed to send magic-link email');
    }
  }

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {
    final r = AccountDeletionRequestEmailBodies.admin(payload);
    await _post(to: to, subject: r.subject, html: r.html, text: r.text);
  }

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {
    final r = AccountDeletionRequestEmailBodies.userConfirmation(payload);
    await _post(to: to, subject: r.subject, html: r.html, text: r.text);
  }

  static String _escapeHtml(String s) => AccountDeletionRequestEmailBodies.escapeHtml(s);
}
