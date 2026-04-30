import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'room_state.freezed.dart';

@freezed
abstract class RoomState extends StateBase with _$RoomState {
  const factory RoomState({
    @Default('') String beaconId,
    @Default(<RoomMessage>[]) List<RoomMessage> messages,
    @Default(<BeaconParticipant>[]) List<BeaconParticipant> participants,
    @Default(<BeaconFactCard>[]) List<BeaconFactCard> factCards,
    BeaconRoomState? roomState,
    @Default(StateIsSuccess()) StateStatus status,
    String? scrollToMessageId,
    String? pendingFactsFocusFactId,

    /// Snapshotted on first successful room load in this session; frozen across refresh.
    DateTime? unreadAnchorAt,

    /// Cleared after mark-seen is flushed (`markSeenNowIfNeeded`) this session.
    @Default(true) bool pendingMarkSeen,

    @Default(true) bool nowCollapsed,

    @Default(true) bool youCollapsed,
  }) = _RoomState;

  const RoomState._();

  /// Earliest unread row: `createdAt` strictly after the snapshotted watermark; all unread when watermark is null.
  String? get firstUnreadMessageId {
    final anchor = unreadAnchorAt;
    for (final m in messages) {
      final isUnread = anchor == null || m.createdAt.isAfter(anchor);
      if (isUnread) return m.id;
    }
    return null;
  }

  int get unreadCount {
    final anchor = unreadAnchorAt;
    if (messages.isEmpty) return 0;
    if (anchor == null) {
      return messages.length;
    }
    var n = 0;
    for (final m in messages) {
      if (m.createdAt.isAfter(anchor)) {
        n++;
      }
    }
    return n;
  }

  /// `-1` if nothing unread / list empty.
  int get firstUnreadIndex {
    final id = firstUnreadMessageId;
    if (id == null) return -1;
    return messages.indexWhere((m) => m.id == id);
  }
}
