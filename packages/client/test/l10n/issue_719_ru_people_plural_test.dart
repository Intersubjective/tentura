import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n.dart';

// #719: ru `one{}` branches used a literal «1», so 21 in the one-category
// read «1 человек». Run after flutter gen-l10n.
void main() {
  final ru = lookupL10n(const Locale('ru'));

  group('post conversation participant counts', () {
    for (final (count, expected) in [
      (1, '1 человек'),
      (2, '2 человека'),
      (5, '5 человек'),
      (21, '21 человек'),
    ]) {
      test('postConversationPeople($count)', () {
        expect(ru.postConversationPeople(count), expected);
      });
    }

    test('postConversationNotOpened', () {
      expect(ru.postConversationNotOpened(1), '1 не открыл');
      expect(ru.postConversationNotOpened(2), '2 не открыли');
      expect(ru.postConversationNotOpened(5), '5 не открыли');
      expect(ru.postConversationNotOpened(21), '21 не открыл');
    });

    test('postConversationDeclined', () {
      expect(ru.postConversationDeclined(1), '1 отказался');
      expect(ru.postConversationDeclined(2), '2 отказались');
      expect(ru.postConversationDeclined(5), '5 отказались');
      expect(ru.postConversationDeclined(21), '21 отказался');
    });
  });

  test('facepileSemantics uses the visible count in the one branch', () {
    expect(ru.facepileSemantics(1, 0), 'Показан 1 человек');
    expect(ru.facepileSemantics(21, 0), 'Показан 21 человек');
  });

  test('beaconRoomReceiptRead uses the count in the one branch', () {
    expect(ru.beaconRoomReceiptRead(1), 'Прочитал 1 человек');
    expect(ru.beaconRoomReceiptRead(21), 'Прочитал 21 человек');
  });
}
