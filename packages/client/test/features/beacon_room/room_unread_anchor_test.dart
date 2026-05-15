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

  test('defaults: pending mark-seen default', () {
    const s = RoomState();
    expect(s.pendingMarkSeen, true);
    expect(s.myUserId, '');
    expect(s.unreadAnchorAt, null);
    expect(s.messages, isEmpty);
    expect(s.status, isA<StateIsSuccess>());
  });

  test('own-authored messages never count as unread (with anchor)', () {
    final anchor = DateTime.utc(2026, 6, 15, 12);
    final s = RoomState(
      myUserId: 'me',
      messages: [
        RoomMessage(
          id: 'mine',
          beaconId: 'b',
          authorId: 'me',
          body: '',
          createdAt: DateTime.utc(2026, 6, 15, 13),
        ),
        RoomMessage(
          id: 'theirs',
          beaconId: 'b',
          authorId: 'other',
          body: '',
          createdAt: DateTime.utc(2026, 6, 15, 13),
        ),
      ],
      unreadAnchorAt: anchor,
    );
    expect(s.unreadCount, 1);
    expect(s.firstUnreadMessageId, 'theirs');
    expect(s.firstUnreadIndex, 1);
  });

  test('null anchor: excludes only own messages from unread count', () {
    final s = RoomState(
      myUserId: 'me',
      messages: [
        RoomMessage(
          id: 'mine',
          beaconId: 'b',
          authorId: 'me',
          body: '',
          createdAt: DateTime.utc(2026),
        ),
        RoomMessage(
          id: 'theirs',
          beaconId: 'b',
          authorId: 'other',
          body: '',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      ],
    );
    expect(s.unreadCount, 1);
    expect(s.firstUnreadMessageId, 'theirs');
  });
}
