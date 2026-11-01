import 'package:logging/logging.dart';

import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// `EMAIL_SUPPRESS_TEST_DOMAINS`: drops every email to a test-class address
/// ([Env.isTestClassEmail]) and delegates the rest. QA magic links are still
/// captured by `QaCapturingEmailSender`, which wraps this sender.
class TestDomainSuppressingEmailSender implements EmailSenderPort {
  TestDomainSuppressingEmailSender(this._env, this._inner);

  static final _log = Logger('TestDomainSuppressingEmailSender');

  final Env _env;
  final EmailSenderPort _inner;

  bool _suppressed(String to, String kind) {
    if (!_env.isTestClassEmail(to)) return false;
    _log.info('suppressed $kind email to test-class address $to');
    return true;
  }

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    if (_suppressed(to, 'magic link')) return;
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
  }) async {
    if (_suppressed(to, 'notification')) return;
    return _inner.sendNotificationEmail(
      to: to,
      locale: locale,
      content: content,
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
    if (_suppressed(to, 'digest')) return;
    return _inner.sendDigestEmail(
      to: to,
      locale: locale,
      content: content,
      listUnsubscribeUrl: listUnsubscribeUrl,
    );
  }

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {
    if (_suppressed(to, 'deletion admin')) return;
    return _inner.sendAccountDeletionRequestAdminEmail(
      to: to,
      payload: payload,
    );
  }

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {
    if (_suppressed(to, 'deletion confirmation')) return;
    return _inner.sendAccountDeletionRequestUserConfirmation(
      to: to,
      payload: payload,
    );
  }
}
