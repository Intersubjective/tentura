import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/util/debug_send_rate_limiter.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_link_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class EmailTestCase extends UseCaseBase {
  EmailTestCase(
    this._contacts,
    this._preferences,
    this._links,
    this._email,
    this._rateLimiter, {
    required super.env,
    required super.logger,
  });

  final VerifiedContactRepositoryPort _contacts;

  final NotificationPreferenceRepositoryPort _preferences;

  final EmailLinkPort _links;

  final EmailSenderPort _email;

  final DebugSendRateLimiter _rateLimiter;

  static const _testTitle = 'Tentura test';

  static const _testBody = 'Email notifications are working.';

  Future<Map<String, Object?>> sendTestEmail({required String userId}) async {
    if (!_rateLimiter.tryAcquire(userId, DebugSendChannel.email)) {
      return _emailTestResult(ok: false, reason: 'rate_limited');
    }

    final email = await _contacts.getPrimaryEmailForAccount(userId);
    if (email == null) {
      return _emailTestResult(ok: false, reason: 'no_email');
    }

    final prefs = await _preferences.getForAccount(userId);
    final manageUrl = _links.manageUrl();
    final unsubscribeUrl = _links.unsubscribeUrl(
      accountId: userId,
      scope: 'asksOfMe',
    );
    final content = EmailNotificationContent(
      item: EmailNotificationItem(
        title: _testTitle,
        body: _testBody,
        url: manageUrl,
      ),
      unsubscribeUrl: unsubscribeUrl,
      managePrefsUrl: manageUrl,
    );

    try {
      await _email.sendNotificationEmail(
        to: email,
        locale: prefs.locale,
        content: content,
        listUnsubscribeUrl: unsubscribeUrl,
      );
      return _emailTestResult(
        ok: true,
        mock: !env.isEmailAuthConfigured,
      );
    } on Object catch (e, st) {
      logger.warning('[Email] test send failed for $userId', e, st);
      return _emailTestResult(ok: false, reason: 'send_failed');
    }
  }

  Map<String, Object?> _emailTestResult({
    required bool ok,
    bool mock = false,
    String? reason,
  }) => {
    'ok': ok,
    'mock': mock,
    if (reason != null) 'reason': reason,
  };
}
