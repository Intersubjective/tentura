import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

part 'beacon_view_state.freezed.dart';

sealed class TimelineEntry implements Comparable<TimelineEntry> {
  DateTime get timestamp;

  @override
  int compareTo(TimelineEntry other) => other.timestamp.compareTo(timestamp);
}

/// Committer joined (one row in commitments tab; not itself a timeline variant).
class TimelineCommitment {
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

  bool get isEdited =>
      !isWithdrawn && updatedAt.difference(createdAt).inSeconds.abs() > 1;
}

/// Committer committed at [createdAt].
class TimelineCommitmentCreated extends TimelineEntry {
  TimelineCommitmentCreated({
    required this.committer,
    required this.message,
    required this.createdAt,
    this.helpType,
  });
  final Profile committer;
  final String message;
  final String? helpType;
  final DateTime createdAt;

  @override
  DateTime get timestamp => createdAt;
}

/// Commitment message/help type changed ([updatedAt]).
class TimelineCommitmentUpdated extends TimelineEntry {
  TimelineCommitmentUpdated({
    required this.committer,
    required this.message,
    required this.updatedAt,
    this.helpType,
  });
  final Profile committer;
  final String message;
  final String? helpType;
  final DateTime updatedAt;

  @override
  DateTime get timestamp => updatedAt;
}

/// Beacon author set/changed coordination response for [committer]'s commitment.
class TimelineAuthorCoordinationResponse extends TimelineEntry {
  TimelineAuthorCoordinationResponse({
    required this.author,
    required this.committer,
    required this.response,
    required this.at,
  });
  final Profile author;
  final Profile committer;
  final CoordinationResponseType response;
  final DateTime at;

  @override
  DateTime get timestamp => at;
}

/// Committer withdrew at [withdrawnAt].
class TimelineCommitmentWithdrawn extends TimelineEntry {
  TimelineCommitmentWithdrawn({
    required this.committer,
    required this.message,
    required this.withdrawnAt,
    this.uncommitReason,
  });
  final Profile committer;
  final String message;
  final String? uncommitReason;
  final DateTime withdrawnAt;

  @override
  DateTime get timestamp => withdrawnAt;
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

/// Beacon author changed lifecycle/state (open/closed/review/etc).
class TimelineBeaconLifecycleChanged extends TimelineEntry {
  TimelineBeaconLifecycleChanged({
    required this.author,
    required this.lifecycle,
    required this.at,
  });

  final Profile author;
  final BeaconLifecycle lifecycle;
  final DateTime at;

  @override
  DateTime get timestamp => at;
}

/// Beacon-level coordination status changed (computed or set by author).
class TimelineBeaconCoordinationStatusChanged extends TimelineEntry {
  TimelineBeaconCoordinationStatusChanged({
    required this.author,
    required this.status,
    required this.at,
  });

  final Profile author;
  final BeaconCoordinationStatus status;
  final DateTime at;

  @override
  DateTime get timestamp => at;
}

class TimelineCreation extends TimelineEntry {
  TimelineCreation({required this.author, required this.createdAt});
  final Profile author;
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

    /// Forward trail + notes (same payload as inbox cards) when the user has an inbox row.
    @Default(InboxProvenance.empty) InboxProvenance forwardProvenance,
    @Default('') String inboxLatestNotePreview,

    /// Forward edges where the current user is the sender for this beacon.
    @Default([]) List<ForwardEdge> myForwards,

    /// V2 `beaconInvolvement` id sets (for recipient reaction icons on [myForwards]).
    @Default({}) Set<String> involvementCommittedIds,
    @Default({}) Set<String> involvementWatchingIds,
    @Default({}) Set<String> involvementOnwardForwarderIds,
    @Default({}) Set<String> involvementRejectedIds,

    /// True when the current user has forwarded this beacon at least once.
    @Default(false) bool hasForwardedThisBeaconOnce,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get isBeaconMine => beacon.author.id == myProfile.id;
  bool get isBeaconNotMine => beacon.author.id != myProfile.id;

  bool get hasFocusedComment => focusCommentId.isNotEmpty;
}
