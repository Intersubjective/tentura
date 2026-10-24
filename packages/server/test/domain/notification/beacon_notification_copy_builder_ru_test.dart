import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';

// #367: the push copy table has Russian for every kind, not only the plan and
// baton rows; English stays as it was.

final _cyrillic = RegExp('[А-Яа-яЁё]');
final _latinWord = RegExp('[A-Za-z]{2,}');

void main() {
  const builder = BeaconNotificationCopyBuilder();

  BeaconNotificationIntent intent(
    NotificationKind kind, {
    int? coordinationItemKind,
    bool promiseWithdrawn = false,
    bool isBackupOffer = false,
  }) => BeaconNotificationIntent(
    kind: kind,
    priority: NotificationPriority.normal,
    beaconId: 'beacon-1',
    actorUserId: 'actor-1',
    coordinationItemKind: coordinationItemKind,
    promiseWithdrawn: promiseWithdrawn,
    isBackupOffer: isBackupOffer,
  );

  /// The words the builder wrote, without the actor's name.
  String own(String text) => text.replaceAll('Anna', '').trim();

  void expectRussian(BeaconNotificationCopy copy, String what) {
    for (final (part, text) in [('title', copy.title), ('body', copy.body)]) {
      final words = own(text);
      if (words.isEmpty) continue; // the title is the actor's name alone
      expect(words, matches(_cyrillic), reason: '$what $part: $text');
      expect(words, isNot(matches(_latinWord)), reason: '$what $part: $text');
    }
  }

  for (final kind in NotificationKind.values) {
    test('${kind.name} has Russian title and body', () {
      final copy = builder.build(
        intent: intent(kind),
        actorDisplayName: 'Anna',
        locale: 'ru',
      );
      expectRussian(copy, kind.name);
    });
  }

  test('withdrawn and backup variants are Russian too', () {
    for (final (name, i) in [
      (
        'promise withdrawn',
        intent(NotificationKind.promiseMade, promiseWithdrawn: true),
      ),
      (
        'help withdrawn',
        intent(NotificationKind.commitmentEvent, promiseWithdrawn: true),
      ),
      (
        'backup offer',
        intent(NotificationKind.commitmentEvent, isBackupOffer: true),
      ),
    ]) {
      expectRussian(
        builder.build(intent: i, actorDisplayName: 'Anna', locale: 'ru'),
        name,
      );
    }
  });

  test('roomAccess reads as an accepted offer in Russian', () {
    final copy = builder.build(
      intent: intent(NotificationKind.roomAccess),
      actorDisplayName: 'Anna',
      locale: 'ru',
    );

    expect(copy.title, 'Anna принял(а) ваше предложение');
    expect(copy.body, 'Ваше предложение принято');
  });

  test('commitment nouns agree in gender in Russian', () {
    String accepted(int itemKind) => builder
        .build(
          intent: intent(
            NotificationKind.commitmentAccepted,
            coordinationItemKind: itemKind,
          ),
          actorDisplayName: 'Anna',
          locale: 'ru',
        )
        .body;

    expect(accepted(coordinationItemKindAsk), 'Ваша просьба принята');
    expect(accepted(coordinationItemKindPromise), 'Ваше обещание принято');
    expect(accepted(coordinationItemKindBlocker), 'Ваш блокер принят');
    expect(
      builder
          .build(
            intent: intent(
              NotificationKind.commitmentCancelled,
              coordinationItemKind: coordinationItemKindBlocker,
            ),
            actorDisplayName: 'Anna',
            locale: 'ru',
          )
          .body,
      'Блокер отменён',
    );
  });

  test('an unnamed actor is «Кто-то» in Russian, Someone in English', () {
    final ru = builder.build(
      intent: intent(NotificationKind.roomAccess),
      actorDisplayName: '',
      locale: 'ru',
    );
    final en = builder.build(
      intent: intent(NotificationKind.roomAccess),
      actorDisplayName: '',
    );

    expect(ru.title, 'Кто-то принял(а) ваше предложение');
    expect(en.title, 'Someone accepted your offer');
  });

  test('English copy is unchanged', () {
    String title(NotificationKind kind) =>
        builder.build(intent: intent(kind), actorDisplayName: 'Anna').title;

    expect(title(NotificationKind.roomAccess), 'Anna accepted your offer');
    expect(title(NotificationKind.commitmentDeclined), 'Offer declined');
    expect(title(NotificationKind.needsMe), 'Asked of you');
    expect(
      builder
          .build(
            intent: intent(NotificationKind.newRelay),
            actorDisplayName: 'Anna',
          )
          .body,
      'Anna forwarded a request to you',
    );
  });
}
