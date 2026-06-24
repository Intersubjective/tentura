import 'package:tentura_server/consts.dart';
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

    final (title, body) = switch (intent.kind) {
      NotificationKind.needsMe => (
          'Asked of you',
          excerpt.isNotEmpty ? excerpt : 'Action needed in the beacon room',
        ),
      NotificationKind.promiseMade => intent.promiseWithdrawn
          ? (
              '$actor withdrew a promise',
              excerpt.isNotEmpty ? excerpt : 'Promise withdrawn',
            )
          : (
              '$actor promised',
              excerpt.isNotEmpty ? excerpt : 'New promise in the beacon room',
            ),
      NotificationKind.coordinationChanged => (
          'Plan updated',
          excerpt.isNotEmpty ? excerpt : 'Coordination changed',
        ),
      NotificationKind.blockerOpened => (
          'Blocker opened',
          excerpt.isNotEmpty ? excerpt : 'A blocker was opened',
        ),
      NotificationKind.blockerResolved => (
          'Blocker resolved',
          excerpt.isNotEmpty ? excerpt : 'A blocker was resolved',
        ),
      NotificationKind.roomAccess => (
          'Room access',
          'You were admitted to the beacon room',
        ),
      NotificationKind.newRelay => (
          actor,
          excerpt.isNotEmpty
              ? '$actor: $excerpt'
              : '$actor forwarded a beacon to you',
        ),
      NotificationKind.commitmentEvent => intent.promiseWithdrawn
          ? (
              actor,
              excerpt.isNotEmpty ? excerpt : '$actor withdrew their help',
            )
          : (
              actor,
              excerpt.isNotEmpty ? excerpt : '$actor offered help',
            ),
      NotificationKind.reviewReady => (
          'Beacon closed — close the loop',
          beaconTitle.isNotEmpty ? beaconTitle : 'Review contributions',
        ),
      NotificationKind.roomActivityLowPriority => (
          beaconTitle.isNotEmpty ? beaconTitle : 'Beacon update',
          excerpt.isNotEmpty ? excerpt : 'New room update',
        ),
      NotificationKind.staleRemind => (
          'Still needs attention',
          excerpt.isNotEmpty ? excerpt : 'Something in the beacon room needs attention',
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
          'New activity in a beacon room',
        ),
      NotificationCategory.ambient => ('Tentura', 'New activity'),
    };
    return BeaconNotificationCopy(
      title: title,
      body: body,
      actionUrl: _actionUrl(intent),
    );
  }

  String _actionUrl(BeaconNotificationIntent intent) {
    final id = intent.beaconId;
    final item = intent.coordinationItemId;
    final itemParam = item != null && item.isNotEmpty ? '&item=$item' : '';

    return switch (intent.kind) {
      NotificationKind.reviewReady => '/#$kPathReviewContributions/$id',
      NotificationKind.commitmentEvent =>
        '/#$kPathAppLinkView?id=$id&dest=people',
      NotificationKind.newRelay => '/#$kPathAppLinkView?id=$id',
      NotificationKind.roomAccess ||
      NotificationKind.needsMe ||
      NotificationKind.staleRemind ||
      NotificationKind.promiseMade ||
      NotificationKind.coordinationChanged ||
      NotificationKind.blockerOpened ||
      NotificationKind.blockerResolved ||
      NotificationKind.roomActivityLowPriority =>
        '/#$kPathAppLinkView?id=$id&dest=room$itemParam',
    };
  }
}
