import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';

void main() {
  const builder = BeaconNotificationCopyBuilder();

  BeaconNotificationIntent intent({
    required NotificationKind kind,
    BeaconKind? beaconKind,
    String bodyExcerpt = '',
  }) => beaconKind == null
      ? BeaconNotificationIntent(
          kind: kind,
          priority: NotificationPriority.normal,
          beaconId: 'beacon-1',
          actorUserId: 'actor-1',
          bodyExcerpt: bodyExcerpt,
        )
      : BeaconNotificationIntent(
          kind: kind,
          priority: NotificationPriority.normal,
          beaconId: 'beacon-1',
          actorUserId: 'actor-1',
          bodyExcerpt: bodyExcerpt,
          beaconKind: beaconKind,
        );

  group('notification intent beacon kind', () {
    test('defaults to a Request', () {
      expect(
        intent(kind: NotificationKind.newRelay).beaconKind,
        BeaconKind.request,
      );
    });
  });

  group('relay copy', () {
    test('a Post arrival says a post was shared with the recipient', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.newRelay,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Jordan',
      );

      expect(copy.title, 'Jordan');
      expect(copy.body, 'Jordan shared a post with you');
    });

    test('a Request arrival still says a request was forwarded', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.newRelay,
          beaconKind: BeaconKind.request,
        ),
        actorDisplayName: 'Jordan',
      );

      expect(copy.body, 'Jordan forwarded a request to you');
    });

    test('a relay without a stated kind is still a Request', () {
      final copy = builder.build(
        intent: intent(kind: NotificationKind.newRelay),
        actorDisplayName: 'Jordan',
      );

      expect(copy.body, 'Jordan forwarded a request to you');
    });
  });

  group('first response copy', () {
    test('without an excerpt says the actor replied to the post', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.postFirstResponse,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Sam',
      );

      expect(copy.title, 'Sam');
      expect(copy.body, 'Sam replied to your post');
    });

    test('with an excerpt shows the excerpt', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.postFirstResponse,
          beaconKind: BeaconKind.post,
          bodyExcerpt: 'Count me in',
        ),
        actorDisplayName: 'Sam',
      );

      expect(copy.body, 'Count me in');
    });
  });

  group('Russian copy', () {
    test('a Post arrival says a post was shared with the recipient', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.newRelay,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Иван',
        locale: 'ru',
      );

      expect(copy.title, 'Иван');
      expect(copy.body, 'Иван поделился постом с вами');
    });

    test('a first response without an excerpt says the actor replied', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.postFirstResponse,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Иван',
        locale: 'ru',
      );

      expect(copy.body, 'Иван откликнулся на ваш пост');
    });

    test('a regional Russian locale code gets the same copy', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.newRelay,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Иван',
        locale: 'ru-RU',
      );

      expect(copy.body, 'Иван поделился постом с вами');
    });

    test('an English locale keeps the English copy', () {
      final copy = builder.build(
        intent: intent(
          kind: NotificationKind.newRelay,
          beaconKind: BeaconKind.post,
        ),
        actorDisplayName: 'Ivan',
        locale: 'en',
      );

      expect(copy.body, 'Ivan shared a post with you');
    });
  });
}
