import 'package:tentura_server/data/service/email/email_sink_writer.dart';
import 'package:tentura_server/data/service/email/resend_email_sender.dart' show ResendEmailSender;
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';

import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// Dev-only delivery sink (`EMAIL_DEBUG_SINK_DIR`): writes the magic link to
/// `<dir>/<sanitized-email>.json` (overwrite = latest link per address) so
/// local and automated flows can read it from disk instead of a mailbox.
/// Selected over [ResendEmailSender] in `EmailSenderModule`; never registered
/// when the env var is unset.
class FileSinkEmailSender implements EmailSenderPort {
  FileSinkEmailSender(this._env);

  final Env _env;

  static const _renderer = EmailTemplateRenderer();

  EmailSinkWriter get _writer => EmailSinkWriter(
    _env.emailDebugSinkDir,
    loggerName: 'FileSinkEmailSender',
  );

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    _writer.write(to, {
      'kind': 'magicLink',
      'to': to,
      'verifyUrl': verifyUrl,
      'inviterName': inviterName,
    });
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    final r = _renderer.renderNotification(content: content, locale: locale);
    _writer.write(to, {
      'kind': 'notification',
      'to': to,
      'locale': locale,
      'subject': r.subject,
      'text': r.text,
      'html': r.html,
      'listUnsubscribeUrl': listUnsubscribeUrl,
    });
  }

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    final r = _renderer.renderDigest(content: content, locale: locale);
    _writer.write(to, {
      'kind': 'digest',
      'to': to,
      'locale': locale,
      'subject': r.subject,
      'text': r.text,
      'html': r.html,
      'itemCount': content.totalItems,
      'listUnsubscribeUrl': listUnsubscribeUrl,
    });
  }

  /// `ada+test@example.com` → `ada_test_example.com` (path-safe, stable).
  static String sanitizeEmailForFileName(String email) =>
      EmailSinkWriter.sanitizeEmailForFileName(email);
}
