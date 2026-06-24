import 'package:test/test.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';

void main() {
  const builder = BeaconNotificationCopyBuilder();

  BeaconNotificationIntent intent({
    required NotificationKind kind,
    String beaconId = 'beacon-1',
    String bodyExcerpt = '',
    String titleExcerpt = '',
    String beaconTitle = '',
    String? coordinationItemId,
    bool promiseWithdrawn = false,
  }) =>
      BeaconNotificationIntent(
        kind: kind,
        priority: NotificationPriority.normal,
        beaconId: beaconId,
        actorUserId: 'actor-1',
        bodyExcerpt: bodyExcerpt,
        titleExcerpt: titleExcerpt,
        beaconTitle: beaconTitle,
        coordinationItemId: coordinationItemId,
        promiseWithdrawn: promiseWithdrawn,
      );

  test('needsMe uses excerpt body and room deep link', () {
    final copy = builder.build(
      intent: intent(
        kind: NotificationKind.needsMe,
        bodyExcerpt: 'Please review the wiring plan',
        coordinationItemId: 'item-9',
      ),
      actorDisplayName: 'Alex',
    );

    expect(copy.title, 'Asked of you');
    expect(copy.body, 'Please review the wiring plan');
    expect(
      copy.actionUrl,
      '/#$kPathAppLinkView?id=beacon-1&dest=room&item=item-9',
    );
  });

  test('promiseMade withdrawn uses withdrawal copy', () {
    final copy = builder.build(
      intent: intent(
        kind: NotificationKind.promiseMade,
        promiseWithdrawn: true,
        bodyExcerpt: 'Will bring tools tomorrow',
      ),
      actorDisplayName: 'Sam',
    );

    expect(copy.title, 'Sam withdrew a promise');
    expect(copy.body, 'Will bring tools tomorrow');
  });

  test('newRelay falls back when excerpt is empty', () {
    final copy = builder.build(
      intent: intent(kind: NotificationKind.newRelay),
      actorDisplayName: 'Jordan',
    );

    expect(copy.title, 'Jordan');
    expect(copy.body, 'Jordan forwarded a beacon to you');
    expect(copy.actionUrl, '/#$kPathAppLinkView?id=beacon-1');
  });

  test('reviewReady uses beacon title and review route', () {
    final copy = builder.build(
      intent: intent(
        kind: NotificationKind.reviewReady,
        beaconTitle: 'Community garden cleanup',
      ),
      actorDisplayName: '',
    );

    expect(copy.title, 'Beacon closed — close the loop');
    expect(copy.body, 'Community garden cleanup');
    expect(copy.actionUrl, '/#$kPathReviewContributions/beacon-1');
  });

  test('empty actor display name becomes Someone in commitment copy', () {
    final copy = builder.build(
      intent: intent(kind: NotificationKind.commitmentEvent),
      actorDisplayName: '',
    );

    expect(copy.title, 'Someone');
    expect(copy.body, 'Someone offered help');
    expect(
      copy.actionUrl,
      '/#$kPathAppLinkView?id=beacon-1&dest=people',
    );
  });

  test('truncates long excerpt in body', () {
    final long = 'x' * 100;
    final copy = builder.build(
      intent: intent(
        kind: NotificationKind.coordinationChanged,
        bodyExcerpt: long,
      ),
      actorDisplayName: 'Alex',
    );

    expect(copy.body.length, 80);
    expect(copy.body.endsWith('…'), isTrue);
  });

  group('lockScreenSafe', () {
    test('redacts excerpt and actor while keeping the deep link', () {
      final i = intent(
        kind: NotificationKind.needsMe,
        bodyExcerpt: 'Secret: review the wiring plan',
        coordinationItemId: 'item-9',
      );
      final safe = builder.lockScreenSafe(i);
      final full = builder.build(intent: i, actorDisplayName: 'Alex');

      expect(safe.body, 'Something needs your response');
      expect(safe.body.contains('Secret'), isFalse);
      expect(safe.title, 'Tentura');
      // Deep link is preserved (not shown on the lock screen).
      expect(safe.actionUrl, full.actionUrl);
    });

    test('uses category-level summary for an unblocking kind', () {
      final safe = builder.lockScreenSafe(
        intent(kind: NotificationKind.reviewReady, beaconTitle: 'Roof repair'),
      );
      expect(safe.body, 'An update is ready for you');
      expect(safe.body.contains('Roof'), isFalse);
    });
  });
}
