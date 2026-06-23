import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/entity/notification_recipient_reason.dart';
import 'package:tentura_server/domain/notification/beacon_notification_recipient_resolver.dart';

void main() {
  const resolver = BeaconNotificationRecipientResolver();

  BeaconNotificationIntent intent({
    required NotificationKind kind,
    String actorUserId = 'actor',
    String? targetPersonId,
    List<String> forwardRecipientIds = const [],
    List<String> admittedUserIds = const [],
    List<String> moderatorUserIds = const [],
    NotificationPriority priority = NotificationPriority.normal,
  }) =>
      BeaconNotificationIntent(
        kind: kind,
        priority: priority,
        beaconId: 'beacon-1',
        actorUserId: actorUserId,
        targetPersonId: targetPersonId,
        forwardRecipientIds: forwardRecipientIds,
        admittedUserIds: admittedUserIds,
        moderatorUserIds: moderatorUserIds,
      );

  BeaconNotificationContext ctx({
    String beaconAuthorId = 'author',
    Set<String> admittedUserIds = const {},
    Set<String> stewardUserIds = const {},
    Set<String> usersWithActiveCoordination = const {},
  }) =>
      BeaconNotificationContext(
        beaconAuthorId: beaconAuthorId,
        admittedUserIds: admittedUserIds,
        stewardUserIds: stewardUserIds,
        usersWithActiveCoordination: usersWithActiveCoordination,
      );

  test('needsMe notifies target and excludes actor', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(
        kind: NotificationKind.needsMe,
        actorUserId: 'actor',
        targetPersonId: 'target',
      ),
      ctx: ctx(),
    );

    expect(recipients, hasLength(1));
    expect(recipients.single.userId, 'target');
    expect(recipients.single.reason, NotificationRecipientReason.targetOfAsk);
  });

  test('promiseMade notifies author, stewards, and affected participant', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(
        kind: NotificationKind.promiseMade,
        targetPersonId: 'affected',
      ),
      ctx: ctx(stewardUserIds: {'steward'}),
    );

    expect(recipients.map((r) => r.userId).toSet(), {'author', 'steward', 'affected'});
    expect(
      recipients.singleWhere((r) => r.userId == 'author').reason,
      NotificationRecipientReason.authorOfBeacon,
    );
  });

  test('coordinationChanged notifies author, admitted members, and active participants', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(kind: NotificationKind.coordinationChanged),
      ctx: ctx(
        admittedUserIds: {'member-a', 'member-b'},
        usersWithActiveCoordination: {'active-1'},
      ),
    );

    expect(
      recipients.map((r) => r.userId).toSet(),
      {'author', 'member-a', 'member-b', 'active-1'},
    );
  });

  test('newRelay notifies forward recipients only', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(
        kind: NotificationKind.newRelay,
        forwardRecipientIds: ['r1', 'r2'],
      ),
      ctx: ctx(),
    );

    expect(recipients.map((r) => r.userId).toSet(), {'r1', 'r2'});
    expect(
      recipients.every(
        (r) => r.reason == NotificationRecipientReason.forwardRecipient,
      ),
      isTrue,
    );
  });

  test('reviewReady notifies admitted participants from intent', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(
        kind: NotificationKind.reviewReady,
        admittedUserIds: ['p1', 'p2'],
      ),
      ctx: ctx(),
    );

    expect(recipients.map((r) => r.userId).toSet(), {'p1', 'p2'});
    expect(
      recipients.every(
        (r) => r.reason == NotificationRecipientReason.reviewParticipant,
      ),
      isTrue,
    );
  });

  test('keeps higher priority when duplicate user appears with lower priority', () {
    final recipients = resolver.resolveRecipients(
      intent: intent(
        kind: NotificationKind.commitmentEvent,
        priority: NotificationPriority.urgent,
        moderatorUserIds: ['steward'],
      ),
      ctx: ctx(stewardUserIds: {'steward'}),
    );

    final steward = recipients.singleWhere((r) => r.userId == 'steward');
    expect(steward.priority, NotificationPriority.urgent);
    expect(steward.reason, NotificationRecipientReason.roomModeratorOrSteward);
  });
}
