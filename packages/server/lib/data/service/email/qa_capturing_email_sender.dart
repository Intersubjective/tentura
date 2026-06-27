import 'package:tentura_server/data/service/email/email_sink_writer.dart';

import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// Remote dev/staging sender: captures magic links for [Env.qaEmailDomains] to
/// [Env.qaEmailCaptureDir] and delegates all other delivery to Resend.
class QaCapturingEmailSender implements EmailSenderPort {
  QaCapturingEmailSender(this._env, this._inner);

  final Env _env;
  final EmailSenderPort _inner;

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    if (_env.isQaAuthEnabled && _env.isQaEmailDomain(to)) {
      EmailSinkWriter(
        _env.qaEmailCaptureDir,
        loggerName: 'QaCapturingEmailSender',
      ).write(to, {
        'kind': 'magicLink',
        'to': to,
        'verifyUrl': verifyUrl,
        'inviterName': inviterName,
      });
      return;
    }
    return _inner.sendMagicLink(
      to: to,
      verifyUrl: verifyUrl,
      inviterName: inviterName,
    );
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) =>
      _inner.sendNotificationEmail(
        to: to,
        locale: locale,
        content: content,
        listUnsubscribeUrl: listUnsubscribeUrl,
      );

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) =>
      _inner.sendDigestEmail(
        to: to,
        locale: locale,
        content: content,
        listUnsubscribeUrl: listUnsubscribeUrl,
      );

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) =>
      _inner.sendAccountDeletionRequestAdminEmail(to: to, payload: payload);

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) =>
      _inner.sendAccountDeletionRequestUserConfirmation(
        to: to,
        payload: payload,
      );
}
