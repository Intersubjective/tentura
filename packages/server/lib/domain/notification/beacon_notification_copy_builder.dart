import 'package:tentura_server/consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_excerpt.dart';

class BeaconNotificationCopy {
  const BeaconNotificationCopy({
    required this.title,
    required this.body,
    required this.actionUrl,
  });

  final String title;
  final String body;
  final String actionUrl;
}

class BeaconNotificationCopyBuilder {
  const BeaconNotificationCopyBuilder();

  BeaconNotificationCopy build({
    required BeaconNotificationIntent intent,
    required String actorDisplayName,
  }) {
    final actor = actorDisplayName.isEmpty ? 'Someone' : actorDisplayName;
    final excerpt = notificationExcerpt(
      intent.bodyExcerpt.isNotEmpty ? intent.bodyExcerpt : intent.titleExcerpt,
    );
    final beaconTitle = intent.beaconTitle.trim();
    final itemNoun = _coordinationItemNoun(intent.coordinationItemKind);

    final (title, body) = switch (intent.kind) {
      NotificationKind.deadlineChanged => (
        'Deadline changed',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'The request deadline changed',
        ),
      ),
      NotificationKind.deadlineReminder => (
        'Deadline reminder',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'This request deadline is tomorrow',
        ),
      ),
      NotificationKind.needsMe => (
        'Asked of you',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Action needed in the request discussion',
        ),
      ),
      NotificationKind.promiseMade =>
        intent.promiseWithdrawn
            ? (
                '$actor withdrew a promise',
                _bodyWithRequest(
                  beaconTitle: beaconTitle,
                  excerpt: excerpt,
                  fallback: 'Promise withdrawn',
                ),
              )
            : (
                '$actor promised',
                _bodyWithRequest(
                  beaconTitle: beaconTitle,
                  excerpt: excerpt,
                  fallback: 'New promise in the request discussion',
                ),
              ),
      NotificationKind.coordinationChanged => (
        'Plan updated',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Coordination changed',
        ),
      ),
      NotificationKind.blockerOpened => (
        'Blocker opened',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'A blocker was opened',
        ),
      ),
      NotificationKind.blockerResolved => (
        'Blocker resolved',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'A blocker was resolved',
        ),
      ),
      NotificationKind.roomAccess => (
        'Offer accepted',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Your offer was accepted',
        ),
      ),
      NotificationKind.commitmentDeclined => (
        'Offer declined',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Your offer was declined',
        ),
      ),
      NotificationKind.commitmentRemoved => (
        'Removed from the discussion',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'You were removed from the request discussion',
        ),
      ),
      NotificationKind.commitmentReleased => (
        'Participation ended',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'The author ended your participation in this request',
        ),
      ),
      NotificationKind.newRelay => (
        actor,
        excerpt.isNotEmpty
            ? '$actor: $excerpt'
            : '$actor forwarded a request to you',
      ),
      NotificationKind.commitmentEvent =>
        intent.promiseWithdrawn
            ? (
                actor,
                excerpt.isNotEmpty ? excerpt : '$actor withdrew their help',
              )
            : intent.isBackupOffer
            ? (
                actor,
                excerpt.isNotEmpty
                    ? excerpt
                    : '$actor offered to help as backup',
              )
            : (
                actor,
                excerpt.isNotEmpty ? excerpt : '$actor offered help',
              ),
      NotificationKind.reviewReady => (
        'Request closed — close the loop',
        beaconTitle.isNotEmpty ? beaconTitle : 'Review contributions',
      ),
      NotificationKind.roomActivityLowPriority => (
        beaconTitle.isNotEmpty ? beaconTitle : 'Request update',
        _bodyWithRequest(
          beaconTitle: '',
          excerpt: excerpt,
          fallback: 'New thread update',
        ),
      ),
      NotificationKind.roomMention => (
        actor,
        excerpt.isNotEmpty ? excerpt : '$actor mentioned you',
      ),
      NotificationKind.staleRemind => (
        'Still needs attention',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Something in the request thread needs attention',
        ),
      ),
      NotificationKind.inviteAccepted => (
        'Invitation accepted',
        '$actor accepted your invitation',
      ),
      NotificationKind.commitmentAccepted => (
        '$actor accepted your $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Your $itemNoun was accepted',
        ),
      ),
      NotificationKind.commitmentResolved => (
        '$actor resolved the $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'The $itemNoun was resolved',
        ),
      ),
      NotificationKind.commitmentCancelled => (
        '$actor cancelled the $itemNoun',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'The $itemNoun was cancelled',
        ),
      ),
      NotificationKind.commitmentRedirected => (
        '$actor reassigned this to you',
        _bodyWithRequest(
          beaconTitle: beaconTitle,
          excerpt: excerpt,
          fallback: 'Open General to see your new assignment',
        ),
      ),
    };

    return BeaconNotificationCopy(
      title: title,
      body: body,
      actionUrl: _actionUrl(intent),
    );
  }

  /// Privacy-safe copy for recipients who enabled lock-screen redaction: a
  /// generic, category-level summary with no excerpts, actor names, or beacon
  /// titles. The deep link is preserved (not shown on the lock screen).
  BeaconNotificationCopy lockScreenSafe(BeaconNotificationIntent intent) {
    final (title, body) = switch (categoryOf(intent.kind)) {
      NotificationCategory.asksOfMe => (
        'Tentura',
        'Something needs your response',
      ),
      NotificationCategory.unblocksMe => (
        'Tentura',
        'An update is ready for you',
      ),
      NotificationCategory.coordination => (
        'Tentura',
        'New activity in a request thread',
      ),
      NotificationCategory.connections => (
        'Tentura',
        'New connection activity',
      ),
      NotificationCategory.ambient => ('Tentura', 'New activity'),
    };
    return BeaconNotificationCopy(
      title: title,
      body: body,
      actionUrl: _actionUrl(intent),
    );
  }

  String _coordinationItemNoun(int? kind) => switch (kind) {
    coordinationItemKindAsk => 'ask',
    coordinationItemKindPromise => 'promise',
    coordinationItemKindBlocker => 'blocker',
    _ => 'commitment',
  };

  String _bodyWithRequest({
    required String beaconTitle,
    required String excerpt,
    required String fallback,
  }) {
    final request = beaconTitle.trim();
    if (excerpt.isNotEmpty) {
      if (request.isNotEmpty) return '$request — $excerpt';
      return excerpt;
    }
    if (request.isNotEmpty) return request;
    return fallback;
  }

  String _actionUrl(BeaconNotificationIntent intent) {
    final id = intent.beaconId;
    final item = intent.coordinationItemId;
    final thread = item != null && item.isNotEmpty ? item : 'general';
    final peopleUrl =
        '/#$kPathBeaconView/$id?tab=people&entry=deep_link&is_deep_link=true';
    final roomUrl =
        '/#$kPathBeaconView/$id?tab=threads&thread=$thread'
        '&entry=deep_link&is_deep_link=true';
    final genericUrl = '/#$kPathBeaconView/$id?is_deep_link=true';

    return switch (intent.kind) {
      NotificationKind.reviewReady => '/#$kPathReviewContributions/$id',
      NotificationKind.commitmentEvent => peopleUrl,
      NotificationKind.commitmentDeclined ||
      NotificationKind.commitmentRemoved ||
      NotificationKind.commitmentReleased => peopleUrl,
      NotificationKind.newRelay => genericUrl,
      NotificationKind.inviteAccepted => '/#/',
      NotificationKind.roomAccess ||
      NotificationKind.needsMe ||
      NotificationKind.staleRemind ||
      NotificationKind.promiseMade ||
      NotificationKind.coordinationChanged ||
      NotificationKind.blockerOpened ||
      NotificationKind.blockerResolved ||
      NotificationKind.roomActivityLowPriority ||
      NotificationKind.roomMention ||
      NotificationKind.commitmentAccepted ||
      NotificationKind.commitmentResolved ||
      NotificationKind.commitmentCancelled ||
      NotificationKind.commitmentRedirected => roomUrl,
      NotificationKind.deadlineChanged ||
      NotificationKind.deadlineReminder => genericUrl,
    };
  }
}
