// Which room messages a Request may be budded from. A Request keeps refusing
// a message that is pinned as a fact; a Post passes `allowLinkedFact: true`,
// because there the source is only a prefill and binds nothing. Every other
// rule (system lines, semantic markers, linked items, polls, thread items)
// still refuses the message in a Post too. Mirrors the server's
// BeaconPromotionEligibilityPolicy.isEligible(allowLinkedFact:).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';

RoomMessage _plain({String? linkedFactCardId}) => RoomMessage(
  id: 'Mplain000001',
  beaconId: 'Bpost0000001',
  authorId: 'Uauthor00001',
  body: 'We need a ladder on Saturday',
  createdAt: DateTime.utc(2026, 11, 2),
  linkedFactCardId: linkedFactCardId,
);

void main() {
  group('a plain authored message', () {
    test('is a bud source in a Request and in a Post', () {
      final message = _plain();
      expect(message.isPromotionEligible(), isTrue);
      expect(message.isPromotionEligible(allowLinkedFact: true), isTrue);
    });
  });

  group('a message pinned as a fact', () {
    final pinned = _plain(linkedFactCardId: 'Ffact0000001');

    test('is not a bud source in a Request (the default)', () {
      expect(pinned.isPromotionEligible(), isFalse);
    });

    test('is a bud source in a Post', () {
      expect(pinned.isPromotionEligible(allowLinkedFact: true), isTrue);
    });
  });

  group('in a Post, every other rule still refuses the message', () {
    final base = _plain(linkedFactCardId: 'Ffact0000001');
    final refused = <String, RoomMessage>{
      'a system line': base.copyWith(systemMessageKind: 1),
      'a semantic marker': base.copyWith(
        semanticMarker: BeaconRoomSemanticMarker.done,
      ),
      'a linked coordination item': base.copyWith(
        linkedItemId: 'Citem0000001',
      ),
      'a linked poll': base.copyWith(linkedPollingId: 'Ppoll0000001'),
      'a thread item': base.copyWith(threadItemId: 'Titem0000001'),
    };
    for (final MapEntry(key: name, value: message) in refused.entries) {
      test('$name is not a bud source', () {
        expect(message.isPromotionEligible(allowLinkedFact: true), isFalse);
      });
    }
  });
}
