import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';

void main() {
  RoomMessage msg(String id, DateTime at) => RoomMessage(
        id: id,
        beaconId: 'b',
        authorId: 'u',
        body: '',
        createdAt: at,
      );

  test('unreadCount: null anchor counts all messages', () {
    final s = RoomState(
      messages: [
        msg('a', DateTime.utc(2026)),
        msg('b', DateTime.utc(2026, 1, 2)),
      ],
    );
    expect(s.unreadCount, 2);
    expect(s.firstUnreadMessageId, 'a');
    expect(s.firstUnreadIndex, 0);
  });

  test('unread helpers: strict after anchor timestamp', () {
    final anchor = DateTime.utc(2026, 6, 15, 12);
    final s = RoomState(
      messages: [
        msg('old', DateTime.utc(2026, 6, 15, 11, 59)),
        msg('border', anchor),
        msg('new', DateTime.utc(2026, 6, 15, 12, 0, 0, 1)),
      ],
      unreadAnchorAt: anchor,
    );
    expect(s.unreadCount, 1);
    expect(s.firstUnreadMessageId, 'new');
    expect(s.firstUnreadIndex, 2);
  });

  test('defaults: strips start collapsed; pending mark-seen default', () {
    const s = RoomState();
    expect(s.nowCollapsed, true);
    expect(s.youCollapsed, true);
    expect(s.pendingMarkSeen, true);
    expect(s.unreadAnchorAt, null);
    expect(s.messages, isEmpty);
    expect(s.status, isA<StateIsSuccess>());
  });
}
