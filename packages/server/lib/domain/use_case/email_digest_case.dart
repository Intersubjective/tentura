import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/email_link_port.dart';
import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/env.dart';

/// Sends the batched "what's waiting / what moved" digest to due accounts.
///
/// emailed_at on the outbox rows is the cadence watermark — once a digest is
/// sent its rows are marked emailed, so the account only re-qualifies after new
/// activity and the cadence window has elapsed.
@injectable
class EmailDigestCase {
  EmailDigestCase(
    this._preferences,
    this._outbox,
    this._contacts,
    this._email,
    this._links,
    this._env,
    this._logger,
  );

  final NotificationPreferenceRepositoryPort _preferences;
  final NotificationOutboxRepositoryPort _outbox;
  final VerifiedContactRepositoryPort _contacts;
  final EmailSenderPort _email;
  final EmailLinkPort _links;
  final Env _env;
  final Logger _logger;

  /// Runs one pass over accounts with pending email, sending digests to those
  /// that are due. Safe to call frequently — it self-gates per account.
  Future<void> runDue({DateTime? now}) async {
    final at = now ?? DateTime.timestamp();
    for (final accountId in await _outbox.accountsWithPendingEmail()) {
      try {
        await _maybeSendFor(accountId, at);
      } on Object catch (e, s) {
        _logger.warning('[Digest] failed for $accountId', e, s);
      }
    }
  }

  Future<void> _maybeSendFor(String accountId, DateTime now) async {
    final prefs = await _preferences.getForAccount(accountId);
    if (prefs.emailDigest == DigestCadence.off) {
      return;
    }
    if (!_isDueHour(prefs, now) || !_cadenceElapsed(prefs, await _last(accountId), now)) {
      return;
    }

    final email = await _contacts.getPrimaryEmailForAccount(accountId);
    if (email == null) {
      return;
    }

    final pending = await _outbox.pendingForAccount(accountId);
    final eligible = pending
        .where((p) => prefs.emailCategories.contains(p.category))
        .toList();
    if (eligible.isEmpty) {
      return;
    }

    final sections = _buildSections(eligible);
    if (sections.isEmpty) {
      return;
    }

    final unsubscribeUrl =
        _links.unsubscribeUrl(accountId: accountId, scope: 'all');
    await _email.sendDigestEmail(
      to: email,
      locale: prefs.locale,
      content: EmailDigestContent(
        sections: sections,
        unsubscribeUrl: unsubscribeUrl,
        managePrefsUrl: _links.manageUrl(),
      ),
      listUnsubscribeUrl: unsubscribeUrl,
    );
    await _outbox.markEmailed([for (final e in eligible) e.id]);
  }

  List<EmailDigestSection> _buildSections(
    List<NotificationOutboxItemEntity> items,
  ) {
    EmailNotificationItem toItem(NotificationOutboxItemEntity i) =>
        EmailNotificationItem(
          title: i.title,
          body: i.body,
          url: _links.absolute(i.actionUrl),
        );

    bool waiting(NotificationCategory c) =>
        c == NotificationCategory.asksOfMe ||
        c == NotificationCategory.unblocksMe;

    final waitingItems = [
      for (final i in items)
        if (waiting(i.category)) toItem(i),
    ];
    final movedItems = [
      for (final i in items)
        if (!waiting(i.category)) toItem(i),
    ];

    return [
      if (waitingItems.isNotEmpty)
        EmailDigestSection(heading: 'Waiting on you', items: waitingItems),
      if (movedItems.isNotEmpty)
        EmailDigestSection(
          heading: 'Moved while you were away',
          items: movedItems,
        ),
    ];
  }

  Future<DateTime?> _last(String accountId) => _outbox.lastEmailedAt(accountId);

  bool _isDueHour(NotificationPreferencesEntity prefs, DateTime now) {
    final local = now.toUtc().add(Duration(minutes: prefs.tzOffsetMinutes));
    return local.hour == _env.emailDigestHour;
  }

  bool _cadenceElapsed(
    NotificationPreferencesEntity prefs,
    DateTime? lastEmailed,
    DateTime now,
  ) {
    if (lastEmailed == null) {
      return true;
    }
    // Slightly under the nominal period so a fixed send-hour isn't skipped.
    final window = prefs.emailDigest == DigestCadence.weekly
        ? const Duration(days: 6, hours: 12)
        : const Duration(hours: 20);
    return now.difference(lastEmailed) >= window;
  }
}
