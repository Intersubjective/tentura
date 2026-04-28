import 'package:freezed_annotation/freezed_annotation.dart';

part 'inbox_room_card_hints.freezed.dart';

/// Extra inbox / My Work lines from V2 inbox room context batch (room + public fact).
@freezed
abstract class InboxRoomCardHints with _$InboxRoomCardHints {
  const factory InboxRoomCardHints({
    required bool isRoomMember,
    required int roomUnreadCount,
    @Default('') String currentPlanSnippet,
    @Default('') String lastRoomMeaningfulChange,
    @Default('') String myNextMove,
    @Default('') String openBlockerTitle,
    @Default('') String publicFactSnippet,
  }) = _InboxRoomCardHints;
}
