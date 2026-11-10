import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';

// localizeStored translates only recognized fixed copy of a stored
// notification; excerpts, names and unknown text pass through unchanged.

void main() {
  const builder = BeaconNotificationCopyBuilder();

  BeaconNotificationIntent intent(NotificationKind kind) =>
      BeaconNotificationIntent(
        kind: kind,
        priority: NotificationPriority.normal,
        beaconId: 'beacon-1',
        actorUserId: 'actor-1',
      );

  BeaconNotificationCopy localize(
    NotificationKind kind, {
    required String title,
    required String body,
    String locale = 'ru',
  }) => builder.localizeStored(
    intent: intent(kind),
    title: title,
    body: body,
    actionUrl: '/#/x',
    locale: locale,
    actorDisplayName: 'Anna',
  );

  group('invite accepted stored bodies', () {
    const cases = {
      'Created an account via your invitation. You are now connected.':
          'Создал(а) аккаунт по вашему приглашению. Теперь вы связаны.',
      'Already had a Tentura account. You are now connected.':
          'Уже был аккаунт в Tentura. Теперь вы связаны.',
      'You are now connected on Tentura.': 'Вы теперь связаны в Tentura.',
    };

    for (final MapEntry(key: en, value: ru) in cases.entries) {
      test('RU: "$en"', () {
        final copy = localize(
          NotificationKind.inviteAccepted,
          title: 'Anna · @anna',
          body: en,
        );
        expect(copy.body, ru);
        expect(copy.title, 'Anna · @anna');
        expect(copy.actionUrl, '/#/x');
      });

      test('EN: "$en" unchanged', () {
        final copy = localize(
          NotificationKind.inviteAccepted,
          title: 'Invitation accepted',
          body: en,
          locale: 'en',
        );
        expect(copy.body, en);
        expect(copy.title, 'Invitation accepted');
      });
    }

    test('unknown body stays as stored', () {
      final copy = localize(
        NotificationKind.inviteAccepted,
        title: 'New connection',
        body: 'You and Boris are now connected.',
      );
      expect(copy.body, 'You and Boris are now connected.');
    });

    test('built English body and title fall back to built Russian', () {
      final copy = localize(
        NotificationKind.inviteAccepted,
        title: 'Invitation accepted',
        body: 'Anna accepted your invitation',
      );
      expect(copy.title, 'Приглашение принято');
      expect(copy.body, 'Anna принял(а) ваше приглашение');
    });
  });

  group('generic kinds', () {
    test('stored body equal to built English becomes Russian', () {
      final copy = localize(
        NotificationKind.deadlineReminder,
        title: 'Deadline reminder',
        body: 'This request deadline is tomorrow',
      );
      expect(copy.title, 'Напоминание о сроке');
      expect(copy.body, 'Срок запроса — завтра');
    });

    test('stored body with a user excerpt stays as stored', () {
      final copy = localize(
        NotificationKind.deadlineReminder,
        title: 'Custom title',
        body: 'Fix the roof — before rain',
      );
      expect(copy.title, 'Custom title');
      expect(copy.body, 'Fix the roof — before rain');
    });

    test('EN locale leaves built English as stored', () {
      final copy = localize(
        NotificationKind.deadlineReminder,
        title: 'Deadline reminder',
        body: 'This request deadline is tomorrow',
        locale: 'en-US',
      );
      expect(copy.title, 'Deadline reminder');
      expect(copy.body, 'This request deadline is tomorrow');
    });
  });
}
