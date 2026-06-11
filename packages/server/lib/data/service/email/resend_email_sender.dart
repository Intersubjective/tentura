import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// Production sender via the Resend API. Registered through
/// `EmailSenderModule` (dev/prod), which swaps in [FileSinkEmailSender] when
/// `EMAIL_DEBUG_SINK_DIR` is set.
class ResendEmailSender implements EmailSenderPort {
  ResendEmailSender(this._env) : _client = http.Client();

  final Env _env;
  final http.Client _client;

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

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
