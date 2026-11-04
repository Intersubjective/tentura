import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/email_link_port.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';
import 'package:tentura_server/domain/port/email_notification_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/env.dart';

@LazySingleton(
  as: EmailNotificationPort,
  env: [Environment.dev, Environment.prod],
)
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
  final EmailLinkPort _links;
  final Env _env;
  final Logger _logger;

  static const _gate = NotificationPreferenceGate();
  static const _copyBuilder = BeaconNotificationCopyBuilder();

  @override
  Future<void> considerImmediate({
    required String recipientUserId,
    required NotificationKind kind,
    required String beaconId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required bool pushDelivered,
  }) async {
    final shares = kind == NotificationKind.newRelay
        ? (await _outbox.pendingForChannelCollapseKey(
                accountId: recipientUserId,
                channelCollapseKey: channelCollapseKey,
              ))
              .where(
                (item) =>
                    item.category == NotificationCategory.postsSharedWithMe &&
                    item.digestPost != null,
              )
              .toList()
        : const <NotificationOutboxItemEntity>[];
    if (kind == NotificationKind.newRelay &&
        !shares.any(
          (item) => item.digestPost?.senderNote.trim().isNotEmpty ?? false,
        )) {
      return;
    }
    final category = shares.isEmpty ? categoryOf(kind) : shares.first.category;
    if (category != NotificationCategory.asksOfMe &&
        category != NotificationCategory.postsSharedWithMe) {
      return;
    }
    if (kNoImmediateEmailKinds.contains(kind)) {
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
      item: shares.isNotEmpty
          ? _copyBuilder.digestPostItem(
              receipts: shares,
              locale: prefs.locale,
              url: _links.absolute(actionUrl),
            )
          : _localizedItem(
              kind: kind,
              beaconId: beaconId,
              title: title,
              body: body,
              actionUrl: actionUrl,
              locale: prefs.locale,
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
      // Prevent the digest from re-sending this collapse family. One send
      // covers the family because U05b coalesces the family into one
      // delivery job.
      await _outbox.markEmailedByChannelCollapseKey(
        accountId: recipientUserId,
        channelCollapseKey: channelCollapseKey,
      );
    } on Object catch (e, s) {
      _logger.warning(
        '[Email] immediate send failed for $recipientUserId',
        e,
        s,
      );
    }
  }

  @override
  Future<bool> considerImmediateByCategory({
    required String recipientUserId,
    required String channelCollapseKey,
    required String title,
    required String body,
    required String actionUrl,
    required String categoryScope,
  }) async {
    final category = notificationCategoryFromName(categoryScope);
    if (category == null) {
      return false;
    }
    // Keep asks-of-me's conservative policy routed through `considerImmediate`.
    if (category == NotificationCategory.asksOfMe ||
        category == NotificationCategory.postsSharedWithMe) {
      return false;
    }

    final prefs = await _preferences.getForAccount(recipientUserId);
    final now = DateTime.timestamp();
    final allowed = _gate.allowsChannel(
      channel: NotificationChannel.email,
      category: category,
      prefs: prefs,
      now: now,
    );
    if (!allowed) {
      return false;
    }

    final email = await _contacts.getPrimaryEmailForAccount(recipientUserId);
    if (email == null) {
      return false;
    }

    // Per-category cooldown (anti-flood).
    final recent = await _outbox.countRecentEmailsByCategory(
      accountId: recipientUserId,
      category: category,
      window: _env.emailNotifCooldown,
    );
    if (recent > 0) {
      return false;
    }

    final unsubscribeUrl = _links.unsubscribeUrl(
      accountId: recipientUserId,
      scope: category.name,
    );
    final content = EmailNotificationContent(
      item: _localizedItem(
        kind: category == NotificationCategory.connections
            ? NotificationKind.inviteAccepted
            : null,
        title: title,
        body: body,
        actionUrl: actionUrl,
        locale: prefs.locale,
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
      await _outbox.markEmailedByChannelCollapseKey(
        accountId: recipientUserId,
        channelCollapseKey: channelCollapseKey,
      );
      return true;
    } on Object catch (e, s) {
      _logger.warning(
        '[Email] immediate send failed for $recipientUserId',
        e,
        s,
      );
      return false;
    }
  }

  EmailNotificationItem _localizedItem({
    required NotificationKind? kind,
    required String title,
    required String body,
    required String actionUrl,
    required String locale,
    String beaconId = '',
  }) {
    final copy = kind == null
        ? BeaconNotificationCopy(title: title, body: body, actionUrl: actionUrl)
        : _copyBuilder.localizeStored(
            intent: BeaconNotificationIntent(
              kind: kind,
              priority: NotificationPriority.high,
              beaconId: beaconId,
              actorUserId: '',
            ),
            title: title,
            body: body,
            actionUrl: actionUrl,
            locale: locale,
          );
    return EmailNotificationItem(
      title: copy.title,
      body: copy.body,
      url: _links.absolute(copy.actionUrl),
    );
  }
}
