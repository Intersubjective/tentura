import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/forward/domain/forward_trail.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';

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
    this.roleLabel,
    this.coordinationResponse,
    this.coordinationResponseAt,
    this.coordinationResponseAuthorId,
    this.withdrawReason,
    this.roomAccess,
    this.admissionAction,
    this.lastDeclineReason,
    this.lastRemoveReason,
    this.stakeState = CommitmentStakeState.none,
    this.offerKind = 0,
    this.isDirectAuthorForward = false,
    this.authorSeenAt,
    this.editedAt,
  });
  final Profile user;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isWithdrawn;
  final String? helpType;
  final String? roleLabel;
  final CoordinationResponseType? coordinationResponse;

  /// When the author last set [coordinationResponse] (accepting the offer
  /// is one); unlike [updatedAt], an edit of the offer leaves it.
  final DateTime? coordinationResponseAt;

  /// Who last set [coordinationResponse]: on an accept, the one who accepted
  /// (the author or a steward, #507).
  final String? coordinationResponseAuthorId;
  final String? withdrawReason;

  /// `beacon_participants.room_access` for this helpOfferer when known.
  final int? roomAccess;
  final HelpOfferAdmissionAction? admissionAction;
  final String? lastDeclineReason;
  final String? lastRemoveReason;
  final CommitmentStakeState stakeState;
  final int offerKind;
  final bool isDirectAuthorForward;
  final DateTime? authorSeenAt;

  /// When the helper last edited the offer's text or help types; null when
  /// never. Unlike [updatedAt], accepting or admitting the offer leaves it
  /// (#361).
  final DateTime? editedAt;

  bool get isEdited => !isWithdrawn && editedAt != null;

  /// [offerKind] of an ordinary offer.
  static const offerKindRegular = 0;

  /// [offerKind] of a backup offer: made by someone who could step in if the
  /// accepted helpers fall through (#596).
  static const offerKindBackup = 1;

  bool get isBackup => offerKind == offerKindBackup;

  TimelineHelpOffer copyWith({
    Profile? user,
    String? message,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isWithdrawn,
    String? helpType,
    String? roleLabel,
    CoordinationResponseType? coordinationResponse,
    DateTime? coordinationResponseAt,
    String? coordinationResponseAuthorId,
    String? withdrawReason,
    int? roomAccess,
    HelpOfferAdmissionAction? admissionAction,
    String? lastDeclineReason,
    String? lastRemoveReason,
    CommitmentStakeState? stakeState,
    int? offerKind,
    bool? isDirectAuthorForward,
    DateTime? authorSeenAt,
    DateTime? editedAt,
  }) => TimelineHelpOffer(
    user: user ?? this.user,
    message: message ?? this.message,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isWithdrawn: isWithdrawn ?? this.isWithdrawn,
    helpType: helpType ?? this.helpType,
    roleLabel: roleLabel ?? this.roleLabel,
    coordinationResponse: coordinationResponse ?? this.coordinationResponse,
    coordinationResponseAt:
        coordinationResponseAt ?? this.coordinationResponseAt,
    coordinationResponseAuthorId:
        coordinationResponseAuthorId ?? this.coordinationResponseAuthorId,
    withdrawReason: withdrawReason ?? this.withdrawReason,
    roomAccess: roomAccess ?? this.roomAccess,
    admissionAction: admissionAction ?? this.admissionAction,
    lastDeclineReason: lastDeclineReason ?? this.lastDeclineReason,
    lastRemoveReason: lastRemoveReason ?? this.lastRemoveReason,
    stakeState: stakeState ?? this.stakeState,
    offerKind: offerKind ?? this.offerKind,
    isDirectAuthorForward: isDirectAuthorForward ?? this.isDirectAuthorForward,
    authorSeenAt: authorSeenAt ?? this.authorSeenAt,
    editedAt: editedAt ?? this.editedAt,
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
  final BeaconStatus status;
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

/// [BeaconViewState.viewerTrail] per state instance: a state is immutable, so
/// its trail never changes (#496).
final _viewerTrailMemo = Expando<List<ForwardEdge>>('viewerTrail');

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
    DateTime? pinnedFactsSeenAt,

    /// From V2 room APIs when the viewer has room access (else empty / null).
    @Default([]) List<BeaconParticipant> roomParticipants,

    /// True after [roomParticipants] has been populated at least once this load.
    @Default(false) bool roomParticipantsLoaded,

    /// Full admitted-helper roster from Hasura (author excluded).
    @Default([]) List<Profile> admittedHelperRoster,

    /// True after [admittedHelperRoster] has been fetched this load.
    @Default(false) bool admittedHelpersLoaded,

    /// Admitted helpers the viewer trusts or worked a past Request with;
    /// fetched only for the showcase (viewer not let in).
    @Default({}) Set<String> teamAcquaintanceIds,

    BeaconRoomState? beaconRoomCue,
    CoordinationItem? openCoordinationBlocker,

    /// Server-backed coordination events (Phase 5+); empty when no room API access.
    @Default([]) List<BeaconActivityEvent> roomActivityEvents,

    /// Explicit YOU-line responsibility counts for the current viewer.
    CoordinationResponsibility? youResponsibility,

    /// Closure snapshot when lifecycle is wrapping up (author status sheet).
    ClosureState? closureState,

    /// Server-derived display projection for author gate fields.
    BeaconDisplayStatusDto? displayStatus,

    @Default(StateIsSuccess()) StateStatus status,

    /// True after a successful beacon content fetch (title, status, etc.).
    @Default(false) bool beaconContentLoaded,

    /// True after the secondary beacon context fetches complete
    /// (help offers, room participants, room state, fact cards, inbox context).
    @Default(false) bool beaconContextLoaded,

    /// Server returned no readable beacon (gated `beacon_by_pk` null).
    @Default(false) bool beaconUnavailable,

    /// The Request's lineage parent, fetched only when the viewer sees the
    /// Request through it (#724): the access banner names a Post parent.
    Beacon? accessParent,

    Object? loadError,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get hasError => loadError != null;

  bool get isBeaconMine => beacon.author.id == myProfile.id;

  /// The author's own live Request that is discoverable in the Field: the
  /// case where "sent to nobody yet" is worth saying (#484).
  bool get _isAuthorsLiveFieldRequest =>
      isBeaconMine &&
      beacon.isRequest &&
      beacon.isDiscoverable &&
      beacon.status == BeaconStatus.open;

  /// The author's forward status is still unknown and worth reading (#484).
  bool get needsAuthorForwardStatus =>
      _isAuthorsLiveFieldRequest && !forwardsLoaded && !forwardsLoading;

  /// This viewer's forward trail ([viewerForwardTrail] of
  /// [viewerForwardEdges]), derived once per state and reused by every helper
  /// tile and the Forwards fold of one build (#496).
  List<ForwardEdge> get viewerTrail =>
      _viewerTrailMemo[this] ??= List.unmodifiable(
        viewerForwardTrail(viewerForwardEdges, viewerUserId: myProfile.id),
      );

  /// [offer] as its helper card tells it: the "forwarded directly" claim
  /// follows this viewer's forward trail, the same data People › Forwards
  /// shows, so the two never disagree (#496).
  TimelineHelpOffer offerOnForwardTrail(TimelineHelpOffer offer) {
    final direct = directAuthorForwardOnViewerTrail(
      serverSaysDirect: offer.isDirectAuthorForward,
      trail: viewerTrail,
      viewerUserId: myProfile.id,
      authorId: beacon.author.id,
      helperId: offer.user.id,
    );
    return direct == offer.isDirectAuthorForward
        ? offer
        : offer.copyWith(isDirectAuthorForward: direct);
  }

  /// A helper card would claim a direct author forward that only this
  /// viewer's forward trail can confirm, and the trail is not read yet
  /// (#496).
  bool get needsTrailForDirectForward =>
      !forwardsLoaded &&
      !forwardsLoading &&
      helpOffers.any(
        (o) =>
            o.isDirectAuthorForward &&
            (isBeaconMine || o.user.id == myProfile.id),
      );

  /// Live in the Field but the author has forwarded it to nobody (#484).
  /// Unknown (forwards not loaded, e.g. the read failed) is not "nobody".
  bool get isLiveSentToNobody =>
      _isAuthorsLiveFieldRequest && forwardsLoaded && myForwards.isEmpty;

  /// The viewer is "inside" the Request: its author or a member let in
  /// (steward, admitted helper, admitted Post addressee). Inside viewers get
  /// the operational HUD; everyone else gets the showcase (#159, #104).
  /// A null access level (local fixtures) keeps the HUD.
  bool get isInsideRequest =>
      isBeaconMine || (beacon.accessLevel?.isMember ?? true);
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

  /// The viewer's offer the author declined, while they have no active one.
  /// Drives the "Your offer was declined" notice on Now (UI review #216).
  TimelineHelpOffer? get myDeclinedHelpOffer {
    if (isBeaconMine || myActiveHelpOffer != null) return null;
    for (final c in helpOffers) {
      if (c.user.id == myProfile.id &&
          c.isWithdrawn &&
          c.admissionAction == HelpOfferAdmissionAction.decline) {
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

  /// A former Post member (addressee) still in the chat who has not offered
  /// help: the intermediate state shown on the Request screen.
  bool get isPostOriginParticipant =>
      !isBeaconMine &&
      !isHelpOffered &&
      roomParticipants.any(
        (p) =>
            p.userId == myProfile.id &&
            p.role == BeaconParticipantRoleBits.addressee &&
            p.roomAccess == RoomAccessBits.admitted,
      );

  /// True for the beacon author or a promoted Steward.
  bool get isAuthorOrSteward => isBeaconMine || isSteward;

  /// Offers «Decline remaining offers» (#268) would decline, as far as this
  /// client can tell: live ordinary offers from people not admitted (an
  /// addressee may be). Backup offers and accepted helpers are left alone.
  /// The server re-checks under its locks and is the authority.
  List<TimelineHelpOffer> get remainingPendingOffers {
    final authorId = beacon.author.id;
    final admittedHelperIds = {for (final p in admittedHelperRoster) p.id};
    final participantById = {for (final p in roomParticipants) p.userId: p};
    return [
      for (final c in helpOffers)
        if (!c.isWithdrawn &&
            c.offerKind == 0 &&
            c.user.id != authorId &&
            c.stakeState != CommitmentStakeState.acknowledged &&
            !admittedHelperIds.contains(c.user.id) &&
            !_admittedOtherThanAddressee(participantById[c.user.id]))
          c,
    ];
  }

  static bool _admittedOtherThanAddressee(BeaconParticipant? p) =>
      p != null &&
      p.roomAccess == RoomAccessBits.admitted &&
      p.role != BeaconParticipantRoleBits.addressee;

  /// «Decline remaining offers» is offered: the author (or a steward) after
  /// «Enough help», with offers still waiting.
  bool get canDeclineRemainingOffers =>
      isAuthorOrSteward &&
      beacon.status == BeaconStatus.enoughHelp &&
      remainingPendingOffers.isNotEmpty;

  /// May create/edit coordination items and the room current line (author,
  /// steward, or admitted room member; mirrors server coordination access).
  bool get canCoordinateInBeaconRoom {
    if (!beacon.status.allowsCoordination) return false;
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

  /// Active (non-withdrawn) help-offerers on the General face pile.
  List<Profile> get activeHelpOfferUsers => [
    for (final offer in helpOffers)
      if (!offer.isWithdrawn) offer.user,
  ];

  /// Room access-unavailable banner applies unless the viewer is waiting on
  /// the author after offering help (Items tab shows waiting copy instead).
  bool get showsRoomAccessUnavailableBanner =>
      !isRoomAdmissionBlocked || coordinationDeniesRoomAdmission;

  /// Pending author triage only — excludes withdrawn offers, helpers already
  /// coordinated, and helpers already in the room (`roomAccess == admitted`
  /// on the offer row or matching participant; auto-admit / direct forward).
  int get unansweredHelpOffersCount {
    final admittedUserIds = {
      for (final p in roomParticipants)
        if (p.roomAccess == RoomAccessBits.admitted) p.userId,
    };
    return helpOffers
        .where(
          (c) =>
              !c.isWithdrawn &&
              c.offerKind == 0 &&
              c.coordinationResponse == null &&
              c.roomAccess != RoomAccessBits.admitted &&
              !admittedUserIds.contains(c.user.id),
        )
        .length;
  }

  int get needCoordinationHelpOffersCount => helpOffers
      .where(
        (c) =>
            !c.isWithdrawn &&
            c.coordinationResponse == CoordinationResponseType.needCoordination,
      )
      .length;
}
