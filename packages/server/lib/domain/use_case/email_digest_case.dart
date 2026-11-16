import 'package:characters/characters.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';
import 'package:tentura_server/domain/notification/notification_text.dart';
import 'package:tentura_server/domain/port/email_link_port.dart';
import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
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
///
/// Every row is rendered at send time from its presentation key and facts
/// plus the recipient's live identity (docs/plans/notification-identity-spec.md
/// §5.1): rows are grouped by Request/Post within a section, never from the
/// stored title/body.
@injectable
class EmailDigestCase {
  EmailDigestCase(
    this._preferences,
    this._outbox,
    this._contacts,
    this._email,
    this._links,
    this._env,
    this._logger, {
    required this._identity,
  });

  final NotificationPreferenceRepositoryPort _preferences;
  final NotificationOutboxRepositoryPort _outbox;
  final VerifiedContactRepositoryPort _contacts;
  final EmailSenderPort _email;
  final EmailLinkPort _links;
  final Env _env;
  final Logger _logger;
  final NotificationIdentityPort _identity;

  static const _copyBuilder = BeaconNotificationCopyBuilder();
  static const _renderer = NotificationCopyRenderer();

  /// Spec §4.3 slot limits, in graphemes.
  static const _headingLimit = 80;

  /// A text-part line is `- {line}`: 160 graphemes with the marker.
  static const _lineLimit = 160 - 2;

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
    if (!_isDueHour(prefs, now) ||
        !_cadenceElapsed(prefs, await _last(accountId), now)) {
      return;
    }

    final email = await _contacts.getPrimaryEmailForAccount(accountId);
    if (email == null) {
      return;
    }

    final eligible = (await _outbox.pendingForAccount(accountId))
        .where((p) => prefs.emailCategories.contains(p.category))
        .where((p) => !kNoDigestKinds.contains(p.kind))
        .toList();
    if (eligible.isEmpty) {
      return;
    }
    final identities = await _identity.resolve(accountId, [
      for (final item in eligible)
        IdentityRequest(
          beaconId: item.beaconId ?? '',
          actorId: item.actorUserId,
          relatedBeaconId:
              item.presentationPayload['relatedBeaconId'] as String?,
        ),
    ]);
    final rows = [
      for (final (index, item) in eligible.indexed)
        if (item.presentationKey case final key?
            when _shown(item, identities[index], now))
          (item: item, key: key, identity: identities[index]),
    ];
    if (rows.isEmpty) {
      return;
    }

    final unsubscribeUrl = _links.unsubscribeUrl(
      accountId: accountId,
      scope: 'all',
    );
    await _email.sendDigestEmail(
      to: email,
      locale: prefs.locale,
      content: EmailDigestContent(
        sections: _buildSections(rows, prefs, now),
        unsubscribeUrl: unsubscribeUrl,
        managePrefsUrl: _links.manageUrl(),
        lockScreenSafe: prefs.lockScreenSafe,
      ),
      listUnsubscribeUrl: unsubscribeUrl,
    );
    // Dropped rows stay pending, as filtered rows always have.
    await _outbox.markEmailed([for (final row in rows) row.item.id]);
  }

  /// Rows the digest may show now (spec §3): not from a blocked person, not
  /// about a deleted entity whose tombstone is unreadable, and no warning for
  /// a Post that has already expired.
  static bool _shown(
    NotificationOutboxItemEntity item,
    NotificationIdentity identity,
    DateTime now,
  ) {
    if (identity.actorHidden) return false;
    if (identity.deleted && !identity.tombstone) return false;
    if (item.kind == NotificationKind.postExpiringSoon) {
      final expiresAt = switch (item.presentationPayload['expiresAt']) {
        final String iso => DateTime.tryParse(iso),
        _ => null,
      };
      if (identity.expired || (expiresAt != null && !expiresAt.isAfter(now))) {
        return false;
      }
    }
    return true;
  }

  List<EmailDigestSection> _buildSections(
    List<
      ({
        NotificationOutboxItemEntity item,
        String key,
        NotificationIdentity identity,
      })
    >
    rows,
    NotificationPreferencesEntity prefs,
    DateTime now,
  ) {
    final headings = _copyBuilder.digestHeadings(prefs.locale);
    final order = [
      headings.postsShared,
      headings.postReplies,
      headings.postsExpiring,
      headings.waiting,
      headings.moved,
      headings.people,
    ];
    String sectionOf(
      NotificationOutboxItemEntity item,
      NotificationIdentity identity,
    ) {
      final beaconId = item.beaconId ?? '';
      if (beaconId.isEmpty) return headings.people;
      if (identity.entityKind == NotificationEntityKind.post) {
        if (item.kind == NotificationKind.newRelay) return headings.postsShared;
        if (item.kind == NotificationKind.postFirstResponse) {
          return headings.postReplies;
        }
        if (item.kind == NotificationKind.postExpiringSoon) {
          return headings.postsExpiring;
        }
      }
      return switch (item.category) {
        NotificationCategory.asksOfMe ||
        NotificationCategory.unblocksMe => headings.waiting,
        _ => headings.moved,
      };
    }

    // Rows arrive newest first, so groups keep their newest event first and
    // lines inside a group stay newest first.
    final drafts = {
      for (final heading in order)
        heading:
            <({String? key, String? label, String url, List<String> lines})>[],
    };
    for (final (:item, :key, :identity) in rows) {
      final copy = _renderer.render(
        presentationKey: key,
        kind: item.kind,
        facts: item.presentationPayload,
        identity: identity,
        locale: prefs.locale,
        tzOffsetMinutes: prefs.tzOffsetMinutes,
        now: now,
      );
      final section = drafts[sectionOf(item, identity)]!;
      final url = _links.absolute(item.actionUrl);
      final label = copy.entityLabel;
      if (label == null) {
        section.add((
          key: null,
          label: null,
          url: url,
          lines: [
            NotificationText.truncate(
              '${copy.headline} — ${copy.sentence}',
              _lineLimit,
            ),
          ],
        ));
        continue;
      }
      final line = _eventLine(copy);
      final group = section.where((d) => d.key == item.beaconId).firstOrNull;
      if (group != null) {
        group.lines.add(line);
      } else {
        section.add((
          key: item.beaconId,
          label: NotificationText.truncate(label, _headingLimit),
          url: url,
          lines: [line],
        ));
      }
    }
    return [
      for (final heading in order)
        if (drafts[heading]!.isNotEmpty)
          EmailDigestSection(
            heading: heading,
            entries: [
              for (final d in drafts[heading]!)
                if (d.label case final label?)
                  EmailDigestGroup(label: label, lines: d.lines, url: d.url)
                else
                  EmailDigestLine(text: d.lines.single, url: d.url),
            ],
          ),
    ];
  }

  /// `L[: {x}]`, the excerpt shortened first to keep the line in its limit.
  static String _eventLine(NotificationCopy copy) {
    final excerpt = copy.excerpt;
    final room = _lineLimit - copy.sentence.characters.length - ': '.length;
    if (excerpt == null || room < 1) {
      return NotificationText.truncate(copy.sentence, _lineLimit);
    }
    return '${copy.sentence}: ${NotificationText.truncate(excerpt, room)}';
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
