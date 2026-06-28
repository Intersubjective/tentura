import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'room_state.freezed.dart';

@freezed
abstract class RoomState extends StateBase with _$RoomState {
  const factory RoomState({
    @Default('') String beaconId,

    /// Non-null when viewing a coordination item thread (not main room).
    String? threadItemId,

    /// Viewer user id; own-authored messages never count as unread.
    @Default('') String myUserId,
    @Default(<RoomMessage>[]) List<RoomMessage> messages,
    @Default(<BeaconParticipant>[]) List<BeaconParticipant> participants,
    @Default(<BeaconFactCard>[]) List<BeaconFactCard> factCards,
    BeaconRoomState? roomState,
    CoordinationItem? openCoordinationBlocker,
    CoordinationItem? currentCoordinationPlan,
    @Default(StateIsSuccess()) StateStatus status,
    String? scrollToMessageId,
    String? pendingFactsFocusFactId,

    /// Snapshotted on first successful room load in this session; frozen across refresh.
    DateTime? unreadAnchorAt,

    /// Cleared after mark-seen is flushed (`markSeenNowIfNeeded`) this session.
    @Default(true) bool pendingMarkSeen,
    Object? loadError,
  }) = _RoomState;

  const RoomState._();

  bool get hasError => loadError != null;

  bool _isUnreadForViewer(RoomMessage m, DateTime? anchor) {
    if (myUserId.isNotEmpty && m.authorId == myUserId) {
      return false;
    }
    return anchor == null || m.createdAt.isAfter(anchor);
  }

  /// Earliest unread row: `createdAt` strictly after the snapshotted watermark; all unread when watermark is null.
  /// Own-authored rows are never unread.
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

  /// `-1` if nothing unread / list empty.
  int get firstUnreadIndex {
    final id = firstUnreadMessageId;
    if (id == null) return -1;
    return messages.indexWhere((m) => m.id == id);
  }

  List<BeaconParticipant> participantsMatchingQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return participants
          .where(
            (p) =>
                p.roomAccess == RoomAccessBits.admitted && p.handle.isNotEmpty,
          )
          .toList(growable: false);
    }
    return participants
        .where(
          (p) =>
              p.roomAccess == RoomAccessBits.admitted &&
              p.handle.isNotEmpty &&
              p.handle.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  /// Active or corrected fact originating from [message].
  BeaconFactCard? factForRoomMessage(RoomMessage message) {
    final lid = message.linkedFactCardId;
    if (lid != null && lid.isNotEmpty) {
      for (final f in factCards) {
        if (f.id == lid) {
          return f;
        }
      }
    }
    for (final f in factCards) {
      if (f.sourceMessageId == message.id) {
        return f;
      }
    }
    return null;
  }
}
