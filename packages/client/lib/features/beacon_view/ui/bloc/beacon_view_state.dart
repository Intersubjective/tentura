import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
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

/// Help offerer joined (one row in helpOffers tab; not itself a timeline variant).
class TimelineHelpOffer {
  TimelineHelpOffer({
    required this.user,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    this.isWithdrawn = false,
    this.helpType,
    this.coordinationResponse,
    this.withdrawReason,
    this.roomAccess,
  });
  final Profile user;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isWithdrawn;
  final String? helpType;
  final CoordinationResponseType? coordinationResponse;
  final String? withdrawReason;
  /// `beacon_participants.room_access` for this helpOfferer when known.
  final int? roomAccess;

  bool get isEdited =>
      !isWithdrawn && updatedAt.difference(createdAt).inSeconds.abs() > 1;

  TimelineHelpOffer copyWith({
    Profile? user,
    String? message,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isWithdrawn,
    String? helpType,
    CoordinationResponseType? coordinationResponse,
    String? withdrawReason,
    int? roomAccess,
  }) =>
      TimelineHelpOffer(
        user: user ?? this.user,
        message: message ?? this.message,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isWithdrawn: isWithdrawn ?? this.isWithdrawn,
        helpType: helpType ?? this.helpType,
        coordinationResponse: coordinationResponse ?? this.coordinationResponse,
        withdrawReason: withdrawReason ?? this.withdrawReason,
        roomAccess: roomAccess ?? this.roomAccess,
      );
}

/// Help offerer offered help at [createdAt].
class TimelineHelpOfferCreated extends TimelineEntry {
  TimelineHelpOfferCreated({
    required this.helpOfferer,
    required this.message,
    required this.createdAt,
    this.helpType,
  });
  final Profile helpOfferer;
  final String message;
  final String? helpType;
  final DateTime createdAt;

  @override
  DateTime get timestamp => createdAt;
}

/// Help offer message/help type changed ([updatedAt]).
class TimelineHelpOfferUpdated extends TimelineEntry {
  TimelineHelpOfferUpdated({
    required this.helpOfferer,
    required this.message,
    required this.updatedAt,
    this.helpType,
  });
  final Profile helpOfferer;
  final String message;
  final String? helpType;
  final DateTime updatedAt;

  @override
  DateTime get timestamp => updatedAt;
}

/// Beacon author set/changed coordination response for [helpOfferer]'s help offer.
class TimelineAuthorCoordinationResponse extends TimelineEntry {
  TimelineAuthorCoordinationResponse({
    required this.author,
    required this.helpOfferer,
    required this.response,
    required this.at,
  });
  final Profile author;
  final Profile helpOfferer;
  final CoordinationResponseType response;
  final DateTime at;

  @override
  DateTime get timestamp => at;
}

/// Help offerer withdrew at [withdrawnAt].
class TimelineHelpOfferWithdrawn extends TimelineEntry {
  TimelineHelpOfferWithdrawn({
    required this.helpOfferer,
    required this.message,
    required this.withdrawnAt,
    this.withdrawReason,
  });
  final Profile helpOfferer;
  final String message;
  final String? withdrawReason;
  final DateTime withdrawnAt;

  @override
  DateTime get timestamp => withdrawnAt;
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
    @Default([]) List<TimelineEntry> timeline,
    @Default([]) List<TimelineHelpOffer> helpOffers,
    @Default(false) bool isHelpOffered,
    @Default(Profile()) Profile myProfile,

    /// Current user's inbox stance for this beacon (`null` = no inbox row).
    InboxItemStatus? inboxStatus,

    /// Forward trail + notes (same payload as inbox cards) when the user has an inbox row.
    @Default(InboxProvenance.empty) InboxProvenance forwardProvenance,
    @Default('') String inboxLatestNotePreview,

    /// Forward edges where the current user is the sender for this beacon.
    @Default([]) List<ForwardEdge> myForwards,

    /// Forward edges involving the viewer (sender or recipient), newest first  -  Forwards screen feed.
    @Default([]) List<ForwardEdge> viewerForwardEdges,

    /// Capability tags per forward edge, keyed by `'${senderId}__${recipientId}'`.
    @Default({}) Map<String, List<String>> forwardReasonSlugs,

    /// V2 `beaconInvolvement` id sets (for recipient reaction icons on [myForwards]).
    @Default({}) Set<String> involvementHelpOfferedIds,
    @Default({}) Set<String> involvementWatchingIds,
    @Default({}) Set<String> involvementOnwardForwarderIds,
    @Default({}) Set<String> involvementRejectedIds,

    /// True when the current user has forwarded this beacon at least once.
    @Default(false) bool hasForwardedThisBeaconOnce,

    /// True after the lazy forwards load has completed at least once this session.
    @Default(false) bool forwardsLoaded,

    /// True while lazy forwards fetch is in flight.
    @Default(false) bool forwardsLoading,

    @Default([]) List<BeaconFactCard> factCards,

    /// From V2 room APIs when the viewer has room access (else empty / null).
    @Default([]) List<BeaconParticipant> roomParticipants,
    BeaconRoomState? beaconRoomCue,
    CoordinationItem? openCoordinationBlocker,

    /// Server-backed coordination events (Phase 5+); empty when no room API access.
    @Default([]) List<BeaconActivityEvent> roomActivityEvents,

    /// Open beacon: viewer has draft evaluation targets (overflow ? draft review).
    @Default(false) bool showDraftEvaluationCta,

    /// From V2 inbox room hints batch; unread messages in beacon room for viewer.
    @Default(0) int roomUnreadCount,

    /// Explicit YOU-line responsibility counts for the current viewer.
    CoordinationResponsibility? youResponsibility,

    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get isBeaconMine => beacon.author.id == myProfile.id;
  bool get isBeaconNotMine => beacon.author.id != myProfile.id;

  /// Active help offer row for the current viewer, if any.
  TimelineHelpOffer? get myActiveHelpOffer {
    for (final c in helpOffers) {
      if (!c.isWithdrawn && c.user.id == myProfile.id) {
        return c;
      }
    }
    return null;
  }

  /// Author signaled this help offer may use the beacon room (`notSuitable` counts as denial).
  ///
  /// Also true when the server auto-admitted the viewer (author direct forward):
  /// `roomAccess` is `RoomAccessBits.admitted` before any coordination row.
  bool get hasRoomAdmission {
    final c = myActiveHelpOffer;
    if (c == null) return false;
    final ra = c.roomAccess;
    if (ra != null && ra == RoomAccessBits.admitted) return true;
    final r = c.coordinationResponse;
    return r != null && r != CoordinationResponseType.notSuitable;
  }

  /// Non-author viewer has offered help but has not received an admitting coordination signal.
  bool get isRoomAdmissionBlocked =>
      !isBeaconMine && isHelpOffered && !hasRoomAdmission;

  /// True when the viewer has been promoted to Beacon Steward.
  bool get isSteward => roomParticipants.any(
    (p) =>
        p.userId == myProfile.id &&
        p.role == BeaconParticipantRoleBits.steward &&
        p.roomAccess == RoomAccessBits.admitted,
  );

  /// True for the beacon author or a promoted Steward.
  bool get isAuthorOrSteward => isBeaconMine || isSteward;

  /// May create/edit coordination items and the room current line (author,
  /// steward, or admitted room member; mirrors server coordination access).
  bool get canCoordinateInBeaconRoom {
    if (!beacon.lifecycle.allowsCoordination) return false;
    if (isAuthorOrSteward) return true;
    if (isHelpOffered && hasRoomAdmission) return true;
    return roomParticipants.any(
      (p) =>
          p.userId == myProfile.id && p.roomAccess == RoomAccessBits.admitted,
    );
  }

  /// Room chip only when the viewer may use room APIs (mirrors server: author,
  /// steward, or admitted participant). Non-authors without a help offer or
  /// coordination admission must not navigate  -  they get [isRoomAdmissionBlocked]
  /// or no room chip.
  bool get canNavigateBeaconRoom =>
      isBeaconMine || isSteward || (isHelpOffered && hasRoomAdmission);

  bool get coordinationDeniesRoomAdmission =>
      myActiveHelpOffer?.coordinationResponse ==
      CoordinationResponseType.notSuitable;

  int get unansweredHelpOffersCount => helpOffers
      .where((c) => !c.isWithdrawn && c.coordinationResponse == null)
      .length;

  int get needCoordinationHelpOffersCount => helpOffers
      .where(
        (c) =>
            !c.isWithdrawn &&
            c.coordinationResponse ==
                CoordinationResponseType.needCoordination,
      )
      .length;

}
