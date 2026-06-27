import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/room_message.dart';

RoomMessage _linkedMessage({
  int messageCount = 0,
  int unreadCount = 0,
}) =>
    RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: 'u1',
      body: 'hello',
      createdAt: DateTime.utc(2026),
      linkedItemId: 'item1',
      linkedItemKind: CoordinationItemKind.ask.value,
      linkedItemStatus: CoordinationItemStatus.open.value,
      linkedItemCreatorId: 'u1',
      linkedItemCreatedAt: DateTime.utc(2026),
      linkedItemUpdatedAt: DateTime.utc(2026),
      linkedItemMessageCount: messageCount,
      linkedItemUnreadCount: unreadCount,
    );

void main() {
  group('RoomMessage.linkedCoordinationItem reply counts', () {
    test('carries joined message/unread counts into the coordination item', () {
      final item = _linkedMessage(messageCount: 3, unreadCount: 1)
          .linkedCoordinationItem!;
      expect(item.messageCount, 3);
      expect(item.unreadCount, 1);
      expect(item.hasUnread, isTrue);
    });

    test('defaults to zero with no unread when not joined', () {
      final item = _linkedMessage().linkedCoordinationItem!;
      expect(item.messageCount, 0);
      expect(item.unreadCount, 0);
      expect(item.hasUnread, isFalse);
    });
  });
}
