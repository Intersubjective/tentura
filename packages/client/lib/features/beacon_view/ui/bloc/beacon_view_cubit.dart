import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/coordination_item/domain/use_case/coordination_item_case.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_people_optimistic.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart'
    show BeaconInvolvementData;
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/beacon_room/domain/entity/room_unread_snapshot.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

import 'package:tentura/features/evaluation/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';

import '../../domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import '../message/help_offer_messages.dart';
import 'beacon_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_view_state.dart';

class BeaconViewCubit extends Cubit<BeaconViewState> {
  BeaconViewCubit({
    required String id,
    required Profile myProfile,
    BeaconViewCase? beaconViewCase,
    CoordinationItemCase? coordinationItemCase,
    UiEffectPort? effects,
  }) : _case = beaconViewCase ?? GetIt.I<BeaconViewCase>(),
       _coordinationItemCase =
           coordinationItemCase ?? GetIt.I<CoordinationItemCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(_idToState(id, myProfile)) {
    _forwardChangesSub = _case.forwardChanges.listen(
      (beaconId) {
        if (isClosed || beaconId != state.beacon.id) return;
        if (_fetchInProgress) {
          _fetchPending = true;
          return;
        }
        unawaited(_runFetchWithGate());
      },
      cancelOnError: false,
    );
    _helpOfferChangesSub = _case.helpOfferChanges.listen(
      (event) {
        if (isClosed || event.beaconId != state.beacon.id) return;
        if (_fetchInProgress) {
          _fetchPending = true;
          return;
        }
        unawaited(_runFetchWithGate());
      },
      cancelOnError: false,
    );
    _beaconRoomRefreshSub = _case.beaconRoomInvalidations.listen(
      _onRoomInvalidation,
      cancelOnError: false,
    );
    _readWatermarkSub = _case.readWatermarkChanges.listen(
      _onReadWatermarkChanged,
      cancelOnError: false,
    );
    unawaited(_runFetchWithGate());
    if (state.loadError != null) {
      _effects.emit(ShowError(state.loadError!));
    }
  }

  final BeaconViewCase _case;

  final CoordinationItemCase _coordinationItemCase;

  final UiEffectPort _effects;

  void _showSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess(), loadError: null));
    }
  }

  late final StreamSubscription<String> _forwardChangesSub;

  late final StreamSubscription<HelpOfferEvent> _helpOfferChangesSub;

  late final StreamSubscription<BeaconRoomInvalidation> _beaconRoomRefreshSub;

  late final StreamSubscription<String> _readWatermarkSub;

  int _serverUnreadCount = 0;
  DateTime? _serverSeenAt;

  bool _fetchInProgress = false;
  bool _fetchPending = false;

  final Set<BeaconRoomEntityType> _pendingRoomTypes = {};

  @override
  Future<void> close() async {
    await _forwardChangesSub.cancel();
    await _helpOfferChangesSub.cancel();
    await _beaconRoomRefreshSub.cancel();
    await _readWatermarkSub.cancel();
    return super.close();
  }

  void _onReadWatermarkChanged(String beaconId) {
    if (isClosed || beaconId != state.beacon.id) return;
    _emitResolvedRoomUnread();
  }

  void _emitResolvedRoomUnread() {
    final count = _case.resolveRoomUnread(
      beaconId: state.beacon.id,
      serverCount: _serverUnreadCount,
      serverSeenAt: _serverSeenAt,
    );
    if (!isClosed && state.roomUnreadCount != count) {
      emit(state.copyWith(roomUnreadCount: count));
    }
  }

  /// Session read-through watermark for main room (survives route pushes).
  DateTime? roomReadThrough(String beaconId) => _case.readThrough(beaconId);

  /// Re-fetches server unread snapshot for the current beacon (e.g. after invalidation).
  Future<void> refreshRoomUnreadCount() => _refreshRoomUnread(state.beacon.id);

  Future<void> moveToWatching() async {
    if (state.inboxStatus != InboxItemStatus.needsMe) return;
    try {
      await _case.setInboxStatus(
        beaconId: state.beacon.id,
        status: InboxItemStatus.watching,
      );
      emit(state.copyWith(inboxStatus: InboxItemStatus.watching));
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> stopWatching() async {
    if (state.inboxStatus != InboxItemStatus.watching) return;
    try {
      await _case.setInboxStatus(
        beaconId: state.beacon.id,
        status: InboxItemStatus.needsMe,
      );
      emit(state.copyWith(inboxStatus: InboxItemStatus.needsMe));
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> rejectInbox({String message = ''}) async {
    if (state.inboxStatus == null) return;
    try {
      await _case.setInboxStatus(
        beaconId: state.beacon.id,
        status: InboxItemStatus.rejected,
        rejectionMessage: message,
      );
      emit(state.copyWith(inboxStatus: InboxItemStatus.rejected));
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> unrejectInbox() async {
    if (state.inboxStatus != InboxItemStatus.rejected) return;
    try {
      await _case.setInboxStatus(
        beaconId: state.beacon.id,
        status: InboxItemStatus.needsMe,
      );
      emit(state.copyWith(inboxStatus: InboxItemStatus.needsMe));
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> delete(String beaconId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.deleteBeacon(beaconId);
      _effects.emit(const NavigateBack());
      emit(state.copyWith(status: const StateIsSuccess()));
    } catch (e) {
      _showSnackError(e);
    }
  }

  /// Lineage fork → new draft id, or null on failure.
  Future<String?> forkFromThis() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final draft = await _case.fork(state.beacon.id);
      emit(state.copyWith(status: StateStatus.isSuccess));
      return draft.id;
    } catch (e) {
      _showSnackError(e);
      return null;
    }
  }

  Future<BeaconCloseResult?> closeBeacon({
    required bool expectedRequiresReviewWindow,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await _case.beaconClose(
        beaconId: state.beacon.id,
        expectedRequiresReviewWindow: expectedRequiresReviewWindow,
      );
      await _fetchBeaconByIdWithTimeline();
      return result;
    } catch (e) {
      _showSnackError(e);
      return null;
    }
  }

  Future<void> cancelBeacon() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.beaconCancel(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> reopenBeacon() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.beaconReopen(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> closeBeaconNow() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.beaconCloseNow(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  /// Refreshes review-window snapshot when lifecycle is wrapping up.
  Future<void> refreshReviewWindowInfo() async {
    if (state.beacon.status != BeaconStatus.reviewOpen) return;
    try {
      final reviewWindowInfo = await _case.fetchReviewWindowStatusIfReviewOpen(
        state.beacon.id,
      );
      if (!isClosed) {
        emit(state.copyWith(reviewWindowInfo: reviewWindowInfo));
      }
    } on Object catch (_) {
      // Keep stale snapshot; never infer Close now from partial data.
    }
  }

  Future<void> extendReview() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.beaconExtendReview(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> archiveBeacon() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.archiveBeacon(state.beacon.id);
      _effects.emit(const NavigateBack());
      emit(state.copyWith(status: const StateIsSuccess()));
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> offerHelp({
    required String message,
    List<String>? helpTypes,
  }) async {
    final wasAlreadyHelpOffered = state.isHelpOffered;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.forwardOfferHelp(
        beaconId: state.beacon.id,
        message: message,
        helpTypes: helpTypes,
        notifyHelpOfferListeners: !wasAlreadyHelpOffered,
      );
      await _fetchBeaconByIdWithTimeline();
      if (!state.hasError && !wasAlreadyHelpOffered) {
        _effects.emit(
          ShowMessage(HelpOfferedForwardNudgeMessage(state.beacon.id)),
        );
      }
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> withdraw({
    required String message,
    required String withdrawReason,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.forwardWithdraw(
        beaconId: state.beacon.id,
        message: message,
        withdrawReason: withdrawReason,
      );
      await _fetchBeaconByIdWithTimeline();
      if (!state.hasError) {
        _effects.emit(const ShowMessage(MovedToInboxMessage()));
      }
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> setCoordinationResponse({
    required String offerUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    final response = coordinationResponseFromSmallint(responseType);
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            coordinationResponse: response,
            roomAccess: patchedHelpOfferRoomAccess(
              current: c.roomAccess,
              inviteToRoom: inviteToRoom,
              removeFromRoom: removeFromRoom,
            ),
          )
        else
          c,
    ];
    final optimisticParticipants = applyCoordinationRoomParticipantPatch(
      participants: state.roomParticipants,
      offerUserId: offerUserId,
      inviteToRoom: inviteToRoom,
      removeFromRoom: removeFromRoom,
    );
    emit(
      state.copyWith(
        helpOffers: optimisticOffers,
        roomParticipants: optimisticParticipants,
      ),
    );
    try {
      await _case.setCoordinationResponse(
        beaconId: state.beacon.id,
        offerUserId: offerUserId,
        responseType: responseType,
        inviteToRoom: inviteToRoom,
        removeFromRoom: removeFromRoom,
      );
      unawaited(_fetchBeaconByIdWithTimeline());
    } catch (e) {
      await _fetchBeaconByIdWithTimeline();
      if (!isClosed) _showSnackError(e);
      rethrow;
    }
  }

  Future<void> acceptHelpOffer({required String offerUserId}) async {
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            coordinationResponse: CoordinationResponseType.useful,
            roomAccess: patchedHelpOfferRoomAccess(
              current: c.roomAccess,
              inviteToRoom: true,
              removeFromRoom: false,
            ),
            admissionAction: HelpOfferAdmissionAction.accept,
          )
        else
          c,
    ];
    final optimisticParticipants = applyCoordinationRoomParticipantPatch(
      participants: state.roomParticipants,
      offerUserId: offerUserId,
      inviteToRoom: true,
      removeFromRoom: false,
    );
    emit(
      state.copyWith(
        helpOffers: optimisticOffers,
        roomParticipants: optimisticParticipants,
      ),
    );
    try {
      await _case.acceptHelpOffer(
        beaconId: state.beacon.id,
        offerUserId: offerUserId,
      );
      unawaited(_fetchBeaconByIdWithTimeline());
    } catch (e) {
      await _fetchBeaconByIdWithTimeline();
      if (!isClosed) _showSnackError(e);
      rethrow;
    }
  }

  Future<void> declineHelpOffer({
    required String offerUserId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            coordinationResponse: CoordinationResponseType.notSuitable,
            admissionAction: HelpOfferAdmissionAction.decline,
            lastDeclineReason: trimmedReason,
          )
        else
          c,
    ];
    emit(state.copyWith(helpOffers: optimisticOffers));
    try {
      await _case.declineHelpOffer(
        beaconId: state.beacon.id,
        offerUserId: offerUserId,
        reason: trimmedReason,
      );
      unawaited(_fetchBeaconByIdWithTimeline());
    } catch (e) {
      await _fetchBeaconByIdWithTimeline();
      if (!isClosed) _showSnackError(e);
      rethrow;
    }
  }

  Future<void> removeFromRoom({
    required String offerUserId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            roomAccess: patchedHelpOfferRoomAccess(
              current: c.roomAccess,
              inviteToRoom: false,
              removeFromRoom: true,
            ),
            admissionAction: HelpOfferAdmissionAction.remove,
            lastRemoveReason: trimmedReason,
          )
        else
          c,
    ];
    final optimisticParticipants = applyCoordinationRoomParticipantPatch(
      participants: state.roomParticipants,
      offerUserId: offerUserId,
      inviteToRoom: false,
      removeFromRoom: true,
    );
    emit(
      state.copyWith(
        helpOffers: optimisticOffers,
        roomParticipants: optimisticParticipants,
      ),
    );
    try {
      await _case.removeFromRoom(
        beaconId: state.beacon.id,
        offerUserId: offerUserId,
        reason: trimmedReason,
      );
      unawaited(_fetchBeaconByIdWithTimeline());
    } catch (e) {
      await _fetchBeaconByIdWithTimeline();
      if (!isClosed) _showSnackError(e);
      rethrow;
    }
  }

  Future<void> publishBeacon() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.publishBeacon(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> setBeaconStatus(
    BeaconStatus status,
  ) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.setBeaconStatus(
        beaconId: state.beacon.id,
        status: status.smallintValue,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    }
  }

  /// Run one stream-triggered full refresh under the concurrency gate.
  ///
  /// At most one gate-guarded fetch runs at a time. If a second invalidation
  /// arrives while one is in flight, the flag is set and a follow-up fetch
  /// starts once the current one finishes. Explicit callers (offerHelp, withdraw,
  /// etc.) call [_fetchBeaconByIdWithTimeline] directly — they already hold
  /// the "source of truth" guarantee because they run after the mutation.
  Future<void> _runFetchWithGate() async {
    _fetchInProgress = true;
    _fetchPending = false;
    _pendingRoomTypes.clear();
    try {
      await _fetchBeaconByIdWithTimeline();
    } finally {
      _fetchInProgress = false;
      if (!isClosed) {
        if (_fetchPending) {
          unawaited(_runFetchWithGate());
        } else if (_pendingRoomTypes.isNotEmpty) {
          final next = {..._pendingRoomTypes};
          _pendingRoomTypes.clear();
          unawaited(_runTargetedFetch(next));
        }
      }
    }
  }

  void _onRoomInvalidation(BeaconRoomInvalidation inv) {
    if (isClosed || inv.beaconId != state.beacon.id) return;
    if (_fetchInProgress) {
      _pendingRoomTypes.add(inv.entityType);
      return;
    }
    unawaited(_runTargetedFetch({inv.entityType}));
  }

  Future<void> _runTargetedFetch(Set<BeaconRoomEntityType> types) async {
    if (types.isEmpty) return;
    _fetchInProgress = true;
    try {
      await _fetchForEntityTypes(types);
    } catch (e) {
      if (!isClosed) _showSnackError(e);
    } finally {
      _fetchInProgress = false;
      if (!isClosed) {
        if (_fetchPending) {
          unawaited(_runFetchWithGate());
        } else if (_pendingRoomTypes.isNotEmpty) {
          final next = {..._pendingRoomTypes};
          _pendingRoomTypes.clear();
          unawaited(_runTargetedFetch(next));
        }
      }
    }
  }

  Future<void> _fetchForEntityTypes(Set<BeaconRoomEntityType> types) async {
    final beaconId = state.beacon.id;
    var needActivity = false;
    var needUnread = false;
    var needParticipants = false;
    var needHelpOffers = false;
    var needRoomState = false;
    var needFactCards = false;
    var needYouResponsibility = false;
    for (final t in types) {
      if (t == BeaconRoomEntityType.roomMessage) {
        needActivity = true;
        needUnread = true;
      } else if (t == BeaconRoomEntityType.activityEvent) {
        needActivity = true;
      } else if (t == BeaconRoomEntityType.participant) {
        needParticipants = true;
        needHelpOffers = true;
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.factCard) {
        needFactCards = true;
      } else if (t == BeaconRoomEntityType.blocker) {
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.coordinationItem) {
        needRoomState = true;
        needActivity = true;
        needYouResponsibility = true;
      }
    }
    await Future.wait([
      if (needActivity) _refreshRoomActivityEvents(beaconId),
      if (needUnread) _refreshRoomUnread(beaconId),
      if (needParticipants) _refreshRoomParticipants(beaconId),
      if (needHelpOffers) _refreshHelpOffers(beaconId),
      if (needRoomState) _refreshBeaconRoomCue(beaconId),
      if (needFactCards) _refreshFactCards(beaconId),
      if (needYouResponsibility) _refreshYouResponsibility(),
    ]);
  }

  Future<void> refreshYouResponsibility() => _refreshYouResponsibility();

  Future<void> _refreshYouResponsibility() async {
    if (isClosed) return;
    try {
      final beaconId = state.beacon.id;
      final responsibility = await _coordinationItemCase.fetchResponsibility(
        beaconId,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          youResponsibility: responsibility.withNewCountsCleared(),
        ),
      );
      await _coordinationItemCase.markItemsSeen(beaconId);
    } on Object catch (_) {
      // YOU line is supplementary; do not fail the screen.
    }
  }

  Future<void> _refreshRoomActivityEvents(String beaconId) async {
    final events = await _case.fetchRoomActivityEvents(beaconId);
    if (!isClosed) emit(state.copyWith(roomActivityEvents: events));
  }

  Future<void> _refreshRoomUnread(String beaconId) async {
    final snapshot = await _case.fetchRoomUnreadSnapshot(beaconId);
    _serverUnreadCount = snapshot.count;
    _serverSeenAt = snapshot.serverSeenAt;
    if (!isClosed && beaconId == state.beacon.id) {
      _emitResolvedRoomUnread();
    }
  }

  Future<void> _refreshRoomParticipants(String beaconId) async {
    final participants = await _case.fetchRoomParticipants(beaconId);
    if (!isClosed) emit(state.copyWith(roomParticipants: participants));
  }

  Future<void> _refreshHelpOffers(String beaconId) async {
    final helpOffers = await _case.fetchHelpOffersWithCoordination(
      beaconId: beaconId,
    );
    if (!isClosed && beaconId == state.beacon.id) {
      emit(
        state.copyWith(
          helpOffers: _timelineHelpOffersFromRemote(helpOffers),
        ),
      );
    }
  }

  List<TimelineHelpOffer> _timelineHelpOffersFromRemote(
    List<
      ({
        String beaconId,
        String userId,
        Profile user,
        String message,
        String? helpType,
        int status,
        String? withdrawReason,
        DateTime createdAt,
        DateTime updatedAt,
        int? responseType,
        DateTime? responseUpdatedAt,
        String? responseAuthorUserId,
        int? roomAccess,
        int? admissionAction,
        String? lastDeclineReason,
        String? lastRemoveReason,
      })
    >
    helpOffers,
  ) => [
    for (final c in helpOffers)
      TimelineHelpOffer(
        user: c.user,
        message: c.message,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        isWithdrawn: c.status == 1,
        helpType: c.helpType,
        coordinationResponse: CoordinationResponseType.tryFromInt(
          c.responseType,
        ),
        withdrawReason: c.withdrawReason,
        roomAccess: c.roomAccess,
        admissionAction: HelpOfferAdmissionAction.tryFromInt(
          c.admissionAction,
        ),
        lastDeclineReason: c.lastDeclineReason,
        lastRemoveReason: c.lastRemoveReason,
      ),
  ];

  Future<void> _refreshBeaconRoomCue(String beaconId) async {
    final cue = await _case.fetchRoomStateIfAllowed(beaconId);
    if (!isClosed && cue != null) {
      emit(state.copyWith(beaconRoomCue: cue));
    }
  }

  /// Refetch room cue after local mutations (echo-suppressed on WS).
  Future<void> refreshBeaconRoomCue({String? savedCurrentLine}) async {
    if (isClosed) return;
    final trimmed = savedCurrentLine?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      final cue = state.beaconRoomCue;
      emit(
        state.copyWith(
          beaconRoomCue:
              cue?.copyWith(currentLine: trimmed) ??
              BeaconRoomState(
                beaconId: state.beacon.id,
                updatedAt: DateTime.now().toUtc(),
                currentLine: trimmed,
              ),
        ),
      );
    }
    await _refreshBeaconRoomCue(state.beacon.id);
  }

  Future<void> _refreshFactCards(String beaconId) async {
    final cards = await _case.fetchFactCards(beaconId);
    if (!isClosed) emit(state.copyWith(factCards: cards));
  }

  Future<void> _fetchBeaconByIdWithTimeline() async {
    try {
      final beaconId = state.beacon.id;
      final myUserId = state.myProfile.id;
      final wasForwardsLoaded = state.forwardsLoaded;

      late final Beacon beacon;
      try {
        beacon = await _fetchBeaconByIdOrRetry(beaconId);
      } on BeaconFetchException {
        if (isClosed) return;
        if (state.timeline.isEmpty && state.helpOffers.isEmpty) {
          emit(
            state.copyWith(
              beaconContentLoaded: false,
              beaconContextLoaded: false,
              beaconUnavailable: true,
              status: const StateIsSuccess(),
            ),
          );
        } else {
          _showSnackError(const BeaconFetchException());
        }
        return;
      }

      if (!isClosed) {
        emit(
          state.copyWith(
            beacon: beacon,
            beaconContentLoaded: true,
            beaconContextLoaded: false,
            beaconUnavailable: false,
            status: StateStatus.isSuccess,
          ),
        );
      }

      final results = await Future.wait([
        _case.fetchHelpOffersWithCoordination(
          beaconId: beaconId,
        ),
        _case.fetchInboxContextForBeacon(beaconId),
        _case.fetchFactCards(beaconId),
        _case.fetchRoomParticipants(beaconId),
        _case.fetchRoomStateIfAllowed(beaconId),
        _case.fetchRoomActivityEvents(beaconId),
        _case.fetchRoomUnreadSnapshot(beaconId),
      ]);

      final helpOffers =
          results[0]!
              as List<
                ({
                  String beaconId,
                  String userId,
                  Profile user,
                  String message,
                  String? helpType,
                  int status,
                  String? withdrawReason,
                  DateTime createdAt,
                  DateTime updatedAt,
                  int? responseType,
                  DateTime? responseUpdatedAt,
                  String? responseAuthorUserId,
                  int? roomAccess,
                  int? admissionAction,
                  String? lastDeclineReason,
                  String? lastRemoveReason,
                })
              >;
      final inboxCtx =
          results[1]!
              as ({
                InboxItemStatus? status,
                InboxProvenance provenance,
                String latestNotePreview,
              });
      final factCards = results[2]! as List<BeaconFactCard>;
      final roomParticipants = results[3]! as List<BeaconParticipant>;
      final beaconRoomCue = results[4] as BeaconRoomState?;
      final roomActivityEvents = results[5]! as List<BeaconActivityEvent>;
      final roomUnreadSnapshot = results[6]! as RoomUnreadSnapshot;
      _serverUnreadCount = roomUnreadSnapshot.count;
      _serverSeenAt = roomUnreadSnapshot.serverSeenAt;
      final roomUnreadCount = _case.resolveRoomUnread(
        beaconId: beaconId,
        serverCount: roomUnreadSnapshot.count,
        serverSeenAt: roomUnreadSnapshot.serverSeenAt,
      );
      final openCoordinationBlocker = beaconRoomCue != null
          ? await _case.fetchOpenCoordinationBlocker(beaconId)
          : null;

      final isHelpOffered = helpOffers
          .where((c) => c.status == 0)
          .any((c) => c.userId == myUserId);

      final helpOffersList = <TimelineHelpOffer>[
        for (final c in helpOffers)
          TimelineHelpOffer(
            user: c.user,
            message: c.message,
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
            isWithdrawn: c.status == 1,
            helpType: c.helpType,
            coordinationResponse: CoordinationResponseType.tryFromInt(
              c.responseType,
            ),
            withdrawReason: c.withdrawReason,
            roomAccess: c.roomAccess,
            admissionAction: HelpOfferAdmissionAction.tryFromInt(
              c.admissionAction,
            ),
            lastDeclineReason: c.lastDeclineReason,
            lastRemoveReason: c.lastRemoveReason,
          ),
      ];

      final helpOfferTimeline = <TimelineEntry>[
        for (final c in helpOffers)
          ...helpOfferRowsToTimelineEntries(beacon: beacon, row: c),
      ];

      final timeline = <TimelineEntry>[
        ...helpOfferTimeline,
        if (beacon.statusChangedAt != null)
          TimelineBeaconCoordinationStatusChanged(
            author: beacon.author,
            status: beacon.status,
            at: beacon.statusChangedAt!,
          ),
        TimelineCreation(author: beacon.author, createdAt: beacon.createdAt),
      ]..sort();

      var showDraftEvaluationCta = false;
      if (beacon.status == BeaconStatus.open) {
        try {
          showDraftEvaluationCta = await _case.beaconHasDraftEvaluationTargets(
            beaconId,
          );
        } on Object catch (_) {
          showDraftEvaluationCta = false;
        }
      }

      ReviewWindowInfo? reviewWindowInfo;
      if (beacon.status == BeaconStatus.reviewOpen) {
        try {
          reviewWindowInfo = await _case.fetchReviewWindowStatusIfReviewOpen(
            beaconId,
          );
        } on Object catch (_) {
          reviewWindowInfo = null;
        }
      }

      emit(
        state.copyWith(
          beacon: beacon,
          timeline: timeline,
          helpOffers: helpOffersList,
          isHelpOffered: isHelpOffered,
          inboxStatus: inboxCtx.status,
          forwardProvenance: inboxCtx.provenance,
          inboxLatestNotePreview: inboxCtx.latestNotePreview,
          factCards: factCards,
          roomParticipants: roomParticipants,
          beaconRoomCue: beaconRoomCue,
          openCoordinationBlocker: openCoordinationBlocker,
          roomActivityEvents: roomActivityEvents,
          showDraftEvaluationCta: showDraftEvaluationCta,
          reviewWindowInfo: reviewWindowInfo,
          roomUnreadCount: roomUnreadCount,
          forwardsLoaded: wasForwardsLoaded,
          beaconContentLoaded: true,
          beaconContextLoaded: true,
          beaconUnavailable: false,
          loadError: null,
          status: StateStatus.isSuccess,
        ),
      );
      if (wasForwardsLoaded) {
        unawaited(_refreshForwards(beaconId, myUserId));
      }
      unawaited(_refreshYouResponsibility());
    } catch (e) {
      if (isClosed) return;
      if (!state.beaconContentLoaded) {
        emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      } else {
        _showSnackError(e);
      }
    }
  }

  /// One retry covers session-token refresh races on cold navigation to beacon view.
  Future<Beacon> _fetchBeaconByIdOrRetry(String beaconId) async {
    try {
      return await _case.fetchBeaconById(beaconId);
    } on BeaconFetchException {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _case.fetchBeaconById(beaconId);
    }
  }

  /// Full reload when the initial fetch failed and the screen has no beacon data.
  Future<void> retryInitialLoad() async {
    emit(
      state.copyWith(
        status: const StateIsLoading(),
        beaconUnavailable: false,
      ),
    );
    await _fetchBeaconByIdWithTimeline();
  }

  /// Lazy-load forwards subsection (People tab). Cached for cubit lifetime.
  Future<void> loadForwards() async {
    if (state.forwardsLoaded || state.forwardsLoading) return;
    emit(state.copyWith(forwardsLoading: true));
    try {
      final beaconId = state.beacon.id;
      final myUserId = state.myProfile.id;
      await _applyForwardsFromRemote(beaconId, myUserId);
      if (!isClosed) {
        emit(
          state.copyWith(
            forwardsLoaded: true,
            forwardsLoading: false,
          ),
        );
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            forwardsLoading: false,
          ),
        );
        _showSnackError(e);
      }
    }
  }

  Future<void> _applyForwardsFromRemote(
    String beaconId,
    String myUserId,
  ) async {
    final results = await Future.wait([
      _case.fetchForwardEdgesForBeacon(beaconId),
      _case.fetchBeaconInvolvement(beaconId: beaconId),
      _case.fetchForwardReasonsByBeacon(beaconId),
    ]);
    final allEdges = results[0] as List<ForwardEdge>;
    final involvement = results[1] as BeaconInvolvementData;
    final reasons = results[2] as Map<String, List<String>>;
    final myForwards = allEdges
        .where((e) => e.sender.id == myUserId)
        .toList(growable: false);
    final viewerEdges = allEdges
        .where(
          (e) => e.sender.id == myUserId || e.recipient.id == myUserId,
        )
        .toList(growable: false);
    if (!isClosed) {
      emit(
        state.copyWith(
          myForwards: myForwards,
          viewerForwardEdges: viewerEdges,
          forwardReasonSlugs: reasons,
          involvementHelpOfferedIds: involvement.helpOfferedIds,
          involvementWatchingIds: involvement.watchingIds,
          involvementOnwardForwarderIds: involvement.onwardForwarderIds,
          involvementRejectedIds: involvement.rejectedIds,
          hasForwardedThisBeaconOnce: myForwards.isNotEmpty,
        ),
      );
    }
  }

  /// Best-effort refresh after main fetch when forwards were already shown.
  Future<void> _refreshForwards(String beaconId, String myUserId) async {
    try {
      await _applyForwardsFromRemote(beaconId, myUserId);
    } on Object catch (_) {
      // Non-fatal: keep existing forwards visible.
    }
  }

  static final _zeroDateTime = DateTime.fromMillisecondsSinceEpoch(0);
  static final _emptyBeacon = Beacon(
    createdAt: _zeroDateTime,
    updatedAt: _zeroDateTime,
  );

  static BeaconViewState _idToState(String id, Profile myProfile) =>
      switch (id) {
        _ when id.startsWith('B') => BeaconViewState(
          beacon: _emptyBeacon.copyWith(id: id),
          myProfile: myProfile,
          status: StateStatus.isLoading,
        ),
        _ => BeaconViewState(
          beacon: _emptyBeacon,
          loadError: 'Wrong id: $id',
        ),
      };
}

/// One help offer row → ordered timeline events (offer / author response / edit / withdraw).
List<TimelineEntry> helpOfferRowsToTimelineEntries({
  required Beacon beacon,
  required ({
    String beaconId,
    String userId,
    Profile user,
    String message,
    String? helpType,
    int status,
    String? withdrawReason,
    DateTime createdAt,
    DateTime updatedAt,
    int? responseType,
    DateTime? responseUpdatedAt,
    String? responseAuthorUserId,
    int? roomAccess,
    int? admissionAction,
    String? lastDeclineReason,
    String? lastRemoveReason,
  })
  row,
}) {
  final author = beacon.author;
  final response = CoordinationResponseType.tryFromInt(row.responseType);
  final events = <TimelineEntry>[];

  if (row.status == 1) {
    events.add(
      TimelineHelpOfferCreated(
        helpOfferer: row.user,
        message: row.message,
        createdAt: row.createdAt,
        helpType: row.helpType,
      ),
    );
    if (response != null &&
        row.responseUpdatedAt != null &&
        !row.responseUpdatedAt!.isAfter(row.updatedAt)) {
      events.add(
        TimelineAuthorCoordinationResponse(
          author: author,
          helpOfferer: row.user,
          response: response,
          at: row.responseUpdatedAt!,
        ),
      );
    }
    events
      ..add(
        TimelineHelpOfferWithdrawn(
          helpOfferer: row.user,
          message: row.message,
          withdrawnAt: row.updatedAt,
          withdrawReason: row.withdrawReason,
        ),
      )
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  events.add(
    TimelineHelpOfferCreated(
      helpOfferer: row.user,
      message: row.message,
      createdAt: row.createdAt,
      helpType: row.helpType,
    ),
  );
  if (response != null && row.responseUpdatedAt != null) {
    events.add(
      TimelineAuthorCoordinationResponse(
        author: author,
        helpOfferer: row.user,
        response: response,
        at: row.responseUpdatedAt!,
      ),
    );
  }
  final edited = row.updatedAt.difference(row.createdAt).inSeconds.abs() > 1;
  if (edited) {
    events.add(
      TimelineHelpOfferUpdated(
        helpOfferer: row.user,
        message: row.message,
        updatedAt: row.updatedAt,
        helpType: row.helpType,
      ),
    );
  }
  events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return events;
}
