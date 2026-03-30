import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/forward/domain/entity/forward_edge.dart';

part 'beacon_view_state.freezed.dart';

sealed class TimelineEntry implements Comparable<TimelineEntry> {
  DateTime get timestamp;

  @override
  int compareTo(TimelineEntry other) =>
      other.timestamp.compareTo(timestamp);
}

class TimelineForward extends TimelineEntry {
  TimelineForward(this.edge);
  final ForwardEdge edge;

  @override
  DateTime get timestamp => edge.createdAt;
}

class TimelineCommitment extends TimelineEntry {
  TimelineCommitment({
    required this.user,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    this.isWithdrawn = false,
  });
  final Profile user;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isWithdrawn;

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
    @Default([]) List<ForwardEdge> forwardEdges,
    @Default(false) bool isCommitted,
    @Default(Profile()) Profile myProfile,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get isBeaconMine => beacon.author.id == myProfile.id;
  bool get isBeaconNotMine => beacon.author.id != myProfile.id;

  bool get hasFocusedComment => focusCommentId.isNotEmpty;
}
