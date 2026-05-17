import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_item_message.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'item_discussion_state.freezed.dart';

@freezed
abstract class ItemDiscussionState extends StateBase
    with _$ItemDiscussionState {
  const factory ItemDiscussionState({
    required CoordinationItem item,
    @Default('') String myUserId,
    @Default([]) List<CoordinationItemMessage> messages,
    @Default(StateIsSuccess()) StateStatus status,

    /// Snapshotted on first successful load; frozen across refresh.
    DateTime? unreadAnchorAt,

    /// Cleared after mark-seen is flushed this session.
    @Default(true) bool pendingMarkSeen,

    /// Open resolution item targeting this item, if any.
    CoordinationItem? pendingResolution,
  }) = _ItemDiscussionState;

  const ItemDiscussionState._();

  bool _isUnreadForViewer(CoordinationItemMessage m, DateTime? anchor) {
    if (myUserId.isNotEmpty && m.senderId == myUserId) {
      return false;
    }
    return anchor == null || m.createdAt.isAfter(anchor);
  }

  String? get firstUnreadMessageId {
    final anchor = unreadAnchorAt;
    for (final m in messages) {
      if (_isUnreadForViewer(m, anchor)) {
        return m.id;
      }
    }
    return null;
  }

  int get unreadCount {
    final anchor = unreadAnchorAt;
    if (messages.isEmpty) return 0;
    var n = 0;
    for (final m in messages) {
      if (_isUnreadForViewer(m, anchor)) {
        n++;
      }
    }
    return n;
  }

  int get firstUnreadIndex {
    final id = firstUnreadMessageId;
    if (id == null) return -1;
    return messages.indexWhere((m) => m.id == id);
  }

  /// Index in the sorted room-message list passed to the chat body.
  int firstUnreadIndexInRoomMessages(List<RoomMessage> roomMessages) {
    final id = firstUnreadMessageId;
    if (id == null) return -1;
    return roomMessages.indexWhere((m) => m.id == id);
  }
}
