import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/ui/message/action_message_base.dart';

void main() {
  group('ForwardLocationMessage', () {
    test('watching copy without pause', () {
      const message = ForwardLocationMessage(beaconId: 'B1');
      expect(message.toEn, 'Request forwarded. It\'s in Watching.');
      expect(message.toRu, 'Запрос переслан. Он во вкладке «Наблюдаю».');
      expect(message.label.toEn, 'Open in Watching');
      expect(message.label.toRu, 'Открыть в «Наблюдаю»');
      expect(message.onPressed, isNotNull);
    });

    test('watching copy with one pause name', () {
      const message = ForwardLocationMessage(
        beaconId: 'B1',
        skippedName: 'Alice',
      );
      expect(
        message.toEn,
        'Request forwarded. It\'s in Watching. — Alice isn\'t taking new requests right now.',
      );
      expect(
        message.toRu,
        'Запрос переслан. Он во вкладке «Наблюдаю». — Alice сейчас не принимает новые запросы.',
      );
    });

    test('watching copy with many pause count', () {
      const message = ForwardLocationMessage(
        beaconId: 'B1',
        skippedCount: 2,
      );
      expect(
        message.toEn,
        'Request forwarded. It\'s in Watching. — 2 people aren\'t taking new requests right now.',
      );
    });

    test('is a LocalizableActionMessage', () {
      const message = ForwardLocationMessage(beaconId: 'B1');
      expect(message, isA<LocalizableActionMessage>());
    });
  });

  group('ForwardLocationMyWorkMessage', () {
    test('my work copy without pause', () {
      const message = ForwardLocationMyWorkMessage();
      expect(message.toEn, 'Request forwarded. It\'s in My Work.');
      expect(message.toRu, 'Запрос переслан. Он в «Моей работе».');
    });

    test('my work copy with pause has no action seam', () {
      const message = ForwardLocationMyWorkMessage(skippedName: 'Bob');
      expect(message, isNot(isA<LocalizableActionMessage>()));
      expect(
        message.toEn,
        'Request forwarded. It\'s in My Work. — Bob isn\'t taking new requests right now.',
      );
    });
  });

  group('ForwardPartialDeliveryMessage', () {
    test('zero delivered keeps availability-only copy', () {
      const message = ForwardPartialDeliveryMessage(
        deliveredCount: 0,
        requestedCount: 1,
        skippedName: 'Alice',
      );
      expect(
        message.toEn,
        'Delivered to 0 of 1 — Alice isn\'t taking new requests right now.',
      );
    });
  });
}
