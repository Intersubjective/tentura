import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/inbox/domain/enum.dart';

part 'beacon_view_state.freezed.dart';

sealed class TimelineEntry implements Comparable<TimelineEntry> {
  DateTime get timestamp;

  @override
  int compareTo(TimelineEntry other) =>
      other.timestamp.compareTo(timestamp);
}

class TimelineCommitment extends TimelineEntry {
  TimelineCommitment({
    required this.user,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    this.isWithdrawn = false,
    this.helpType,
    this.coordinationResponse,
    this.uncommitReason,
  });
  final Profile user;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isWithdrawn;
  final String? helpType;
  final CoordinationResponseType? coordinationResponse;
  final String? uncommitReason;

  @override
  DateTime get timestamp =>
      isWithdrawn ? updatedAt : createdAt;

  bool get isEdited =>
      !isWithdrawn &&
      updatedAt.difference(createdAt).inSeconds.abs() > 1;
}

class TimelineUpdate extends TimelineEntry {
  TimelineUpdate({
    required this.author,
    required this.content,
    required this.createdAt,
  });
  final Profile author;
  final String content;
  final DateTime createdAt;

  @override
  DateTime get timestamp => createdAt;
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BeaconViewState extends StateBase with _$BeaconViewState {
  const factory BeaconViewState({
    required Beacon beacon,
    @Default('') String focusCommentId,
    @Default([]) List<TimelineEntry> timeline,
    @Default([]) List<TimelineCommitment> commitments,
    @Default(false) bool isCommitted,
    @Default(Profile()) Profile myProfile,
    /// Current user's inbox stance for this beacon (`null` = no inbox row).
    InboxItemStatus? inboxStatus,
    /// True when the current user has forwarded this beacon at least once.
    @Default(false) bool hasForwardedThisBeaconOnce,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get isBeaconMine => beacon.author.id == myProfile.id;
  bool get isBeaconNotMine => beacon.author.id != myProfile.id;

  bool get hasFocusedComment => focusCommentId.isNotEmpty;
}
