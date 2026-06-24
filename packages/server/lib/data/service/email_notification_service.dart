import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/env.dart';

@LazySingleton(as: EmailNotificationPort, env: [Environment.dev, Environment.prod])
class EmailNotificationService implements EmailNotificationPort {
  EmailNotificationService(
    this._preferences,
    this._presence,
    this._email,
    this._contacts,
    this._outbox,
    this._links,
    this._env,
    this._logger,
  );

  final NotificationPreferenceRepositoryPort _preferences;
  final UserPresenceRepositoryPort _presence;
  final EmailSenderPort _email;
  final VerifiedContactRepositoryPort _contacts;
  final NotificationOutboxRepositoryPort _outbox;
  final EmailLinkBuilder _links;
  final Env _env;
  final Logger _logger;

  static const _gate = NotificationPreferenceGate();

  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String dedupKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {
    final category = categoryOf(kind);
    // Immediate email is reserved for the highest-stakes category.
    if (category != NotificationCategory.asksOfMe) {
      return;
    }

    final prefs = await _preferences.getForAccount(recipientUserId);
    final presence = await _presence.get(recipientUserId);
    final now = DateTime.timestamp();
    final decision = _gate.decideEmail(
      category: category,
      prefs: prefs,
      presence: presence,
      pushDelivered: pushDelivered,
      now: now,
      beaconId: beaconId.isEmpty ? null : beaconId,
    );
    if (decision != EmailDecision.immediate) {
      return;
    }

    final email = await _contacts.getPrimaryEmailForAccount(recipientUserId);
    if (email == null) {
      return;
    }

    // Per-category cooldown (anti-flood).
    final recent = await _outbox.countRecentEmailsByCategory(
      accountId: recipientUserId,
      category: category,
      window: _env.emailNotifCooldown,
    );
    if (recent > 0) {
      return;
    }

    final unsubscribeUrl = _links.unsubscribeUrl(
      accountId: recipientUserId,
      scope: category.name,
    );
    final content = EmailNotificationContent(
      item: EmailNotificationItem(
        title: title,
        body: body,
        url: _links.absolute(actionUrl),
      ),
      unsubscribeUrl: unsubscribeUrl,
      managePrefsUrl: _links.manageUrl(),
    );

    try {
      await _email.sendNotificationEmail(
        to: email,
        locale: prefs.locale,
        content: content,
        listUnsubscribeUrl: unsubscribeUrl,
      );
      // Prevent the digest from re-sending the same row.
      await _outbox.markEmailedByDedupKey(dedupKey);
    } on Object catch (e, s) {
      _logger.warning('[Email] immediate send failed for $recipientUserId', e, s);
    }
  }
}
