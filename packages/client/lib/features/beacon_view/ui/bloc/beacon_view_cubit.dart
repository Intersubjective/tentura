import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_people_optimistic.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/help_offer_admission_action.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart'
    show BeaconInvolvementData;
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/features/beacon/ui/util/beacon_delete_ui.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/beacon_threads/domain/entity/room_unread_snapshot.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

import 'package:tentura/features/evaluation/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';

import '../../domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_pin_after_message_exception.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/features/beacon_threads/ui/message/beacon_room_fact_messages.dart';
import '../message/help_offer_messages.dart';
import 'beacon_view_state.dart';
import 'timeline_help_offer_mapping.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_view_state.dart';

class BeaconViewCubit extends Cubit<BeaconViewState> {
  BeaconViewCubit({
    required String id,
    required Profile myProfile,
    BeaconViewCase? beaconViewCase,
    UiEffectPort? effects,
  }) : _case = beaconViewCase ?? GetIt.I<BeaconViewCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(_idToState(id, myProfile)) {
    final seen = _case.pinnedFactsSeenAt(id, myProfile.id);
    if (seen != null) {
      emit(state.copyWith(pinnedFactsSeenAt: seen));
    }
    _forwardChangesSub = _case.forwardChanges.listen(
      _requestFullRefreshFor,
      cancelOnError: false,
    );
    _helpOfferChangesSub = _case.helpOfferChanges.listen(
      (event) => _requestFullRefreshFor(event.beaconId),
      cancelOnError: false,
    );
    _beaconChangesSub = _case.beaconChanges.listen(
      (event) {
        if (event is RepositoryEventInvalidate<Beacon> ||
            event is RepositoryEventUpdate<Beacon>) {
          _requestFullRefreshFor(event.id);
        }
      },
      cancelOnError: false,
    );
    _beaconRoomRefreshSub = _case.beaconRoomInvalidations.listen(
      _onRoomInvalidation,
      cancelOnError: false,
    );
    _catchUpsSub = _case.catchUps.listen(
      (_) => _requestFullRefresh(),
      cancelOnError: false,
    );
    _peopleChangesSub = _case.peopleChanges.listen(
      _onPeopleChanged,
      cancelOnError: false,
    );
    unawaited(_runFetchWithGate(background: false));
    if (state.loadError != null) {
      _effects.emit(ShowError(state.loadError!));
    }
  }

  final BeaconViewCase _case;

  final UiEffectPort _effects;

  void _showSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess(), loadError: null));
    }
  }

  bool _rejectIfDiscussionReadOnly() {
    if (state.beacon.status.allowsDiscussionWrites) return false;
    _effects.emit(const ShowMessage(DiscussionReadOnlyMessage()));
    return true;
  }

  late final StreamSubscription<String> _forwardChangesSub;

  late final StreamSubscription<HelpOfferEvent> _helpOfferChangesSub;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChangesSub;

  late final StreamSubscription<BeaconRoomInvalidation> _beaconRoomRefreshSub;

  late final StreamSubscription<void> _catchUpsSub;

  late final StreamSubscription<RealtimeEntityChange> _peopleChangesSub;

  bool _fetchInProgress = false;
  bool _fetchPending = false;

  final Set<BeaconRoomEntityType> _pendingRoomTypes = {};

  @override
  Future<void> close() async {
    await _forwardChangesSub.cancel();
    await _helpOfferChangesSub.cancel();
    await _beaconChangesSub.cancel();
    await _beaconRoomRefreshSub.cancel();
    await _catchUpsSub.cancel();
    await _peopleChangesSub.cancel();
    return super.close();
  }

  void _requestFullRefreshFor(String beaconId) {
    if (beaconId != state.beacon.id) return;
    _requestFullRefresh();
  }

  void _requestFullRefresh() {
    if (isClosed) return;
    if (_fetchInProgress) {
      _fetchPending = true;
      return;
    }
    unawaited(_runFetchWithGate());
  }

  void _onPeopleChanged(RealtimeEntityChange change) {
    if (change.kind == RealtimeEntityKind.relationship ||
        _visiblePeopleIds().contains(change.aggregateId)) {
      _requestFullRefresh();
    }
  }

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
    if (state.status == StateStatus.isLoading) return;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.deleteBeacon(beaconId);
      _effects.emit(const NavigateBack());
      emit(state.copyWith(status: const StateIsSuccess()));
    } catch (_) {
      emit(state.copyWith(status: const StateIsSuccess()));
      _effects.emit(
        ShowMessage(
          BeaconDeleteFailedMessage(() => unawaited(delete(beaconId))),
        ),
      );
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
    if (state.status == StateStatus.isLoading) return null;
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
    } finally {
      if (!isClosed && state.status == StateStatus.isLoading) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
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
    if (state.status == StateStatus.isLoading) return;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.beaconCloseNow(state.beacon.id);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      _showSnackError(e);
    } finally {
      if (!isClosed && state.status == StateStatus.isLoading) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
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
    final wasEnoughHelp = state.beacon.status == BeaconStatus.enoughHelp;
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
          ShowMessage(
            wasEnoughHelp
                ? const BackupOfferSentMessage()
                : HelpOfferedForwardNudgeMessage(state.beacon.id),
          ),
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
    final effectiveInviteToRoom =
        inviteToRoom &&
        CoordinationResponseType.allowsInviteToRoomForResponseType(
          responseType,
        );
    final response = coordinationResponseFromSmallint(responseType);
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            coordinationResponse: response,
            roomAccess: patchedHelpOfferRoomAccess(
              current: c.roomAccess,
              inviteToRoom: effectiveInviteToRoom,
              removeFromRoom: removeFromRoom,
            ),
          )
        else
          c,
    ];
    final optimisticParticipants = applyCoordinationRoomParticipantPatch(
      participants: state.roomParticipants,
      offerUserId: offerUserId,
      inviteToRoom: effectiveInviteToRoom,
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
        inviteToRoom: effectiveInviteToRoom,
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

  Future<void> releaseCommitment({
    required String offerUserId,
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    final optimisticOffers = [
      for (final c in state.helpOffers)
        if (c.user.id == offerUserId)
          c.copyWith(
            stakeState: CommitmentStakeState.released,
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
      await _case.releaseCommitment(
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
  Future<void> _runFetchWithGate({bool background = true}) async {
    _fetchInProgress = true;
    _fetchPending = false;
    _pendingRoomTypes.clear();
    try {
      await _fetchBeaconByIdWithTimeline(background: background);
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
    // Room kinds with request_detail impact must also converge the beacon
    // lifecycle and its derived header context, not just the room slices.
    if (inv.entityType == BeaconRoomEntityType.coordinationItem ||
        inv.entityType == BeaconRoomEntityType.participant ||
        inv.entityType == BeaconRoomEntityType.factCard) {
      _requestFullRefresh();
      return;
    }
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
    } on Object catch (_) {
      // Keep the usable snapshot. A later hint, catch-up, or manual action
      // retries targeted background convergence without a duplicate UI effect.
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
    var needParticipants = false;
    var needHelpOffers = false;
    var needRoomState = false;
    var needFactCards = false;
    for (final t in types) {
      if (t == BeaconRoomEntityType.roomMessage) {
        needActivity = true;
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.roomSeen) {
        // Threads list owns thread-keyed unread; beacon view no longer tracks batch count.
      } else if (t == BeaconRoomEntityType.activityEvent) {
        needActivity = true;
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.participant) {
        needParticipants = true;
        needHelpOffers = true;
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.factCard) {
        needFactCards = true;
      } else if (t == BeaconRoomEntityType.coordinationItem) {
        needRoomState = true;
        needActivity = true;
      }
    }
    await Future.wait([
      if (needActivity) _refreshRoomActivityEvents(beaconId),
      if (needParticipants) _refreshRoomParticipants(beaconId),
      if (needHelpOffers) _refreshHelpOffers(beaconId),
      if (needRoomState) _refreshBeaconRoomCue(beaconId),
      if (needFactCards) _refreshFactCards(beaconId),
    ]);
  }

  Future<void> _refreshRoomActivityEvents(String beaconId) async {
    final events = await _case.fetchRoomActivityEvents(beaconId);
    if (!isClosed) emit(state.copyWith(roomActivityEvents: events));
  }

  Future<void> _refreshRoomParticipants(String beaconId) async {
    final participants = await _case.fetchRoomParticipants(beaconId);
    if (!isClosed && beaconId == state.beacon.id) {
      emit(
        state.copyWith(
          roomParticipants: participants,
          roomParticipantsLoaded: true,
        ),
      );
    }
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
        int stakeState,
        int offerKind,
        bool isDirectAuthorForward,
      })
    >
    helpOffers,
  ) => timelineHelpOffersFromRemote(helpOffers);

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
    if (isClosed) return;
    _hydratePinnedFactsSeen(beaconId, cards);
    emit(
      state.copyWith(
        factCards: cards,
        pinnedFactsSeenAt: _case.pinnedFactsSeenAt(
          beaconId,
          state.myProfile.id,
        ),
      ),
    );
  }

  void _hydratePinnedFactsSeen(String beaconId, List<BeaconFactCard> cards) {
    _case.baselinePinnedFactsIfNeeded(
      beaconId: beaconId,
      userId: state.myProfile.id,
      facts: cards,
    );
  }

  void markPinnedFactsSeen() {
    _case.markPinnedFactsSeen(
      beaconId: state.beacon.id,
      userId: state.myProfile.id,
      facts: state.factCards,
    );
    if (isClosed) return;
    emit(
      state.copyWith(
        pinnedFactsSeenAt: _case.pinnedFactsSeenAt(
          state.beacon.id,
          state.myProfile.id,
        ),
      ),
    );
  }

  Future<void> correctFact({
    required String factCardId,
    required String newText,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.correctFact(
        beaconId: state.beacon.id,
        factCardId: factCardId,
        newText: newText,
      );
      await _refreshFactCards(state.beacon.id);
      _effects.emit(const ShowMessage(BeaconFactEditSuccessMessage()));
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> removeFact({required String factCardId}) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.removeFact(
        beaconId: state.beacon.id,
        factCardId: factCardId,
      );
      await _refreshFactCards(state.beacon.id);
      _effects.emit(const ShowMessage(BeaconFactRemoveSuccessMessage()));
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<void> setFactVisibility({
    required String factCardId,
    required int visibility,
  }) async {
    if (_rejectIfDiscussionReadOnly()) return;
    try {
      await _case.setFactVisibility(
        beaconId: state.beacon.id,
        factCardId: factCardId,
        visibility: visibility,
      );
      await _refreshFactCards(state.beacon.id);
      _effects.emit(const ShowMessage(BeaconFactVisibilitySuccessMessage()));
    } on Object catch (e) {
      _showSnackError(e);
    }
  }

  Future<bool> pinFactFromComposer({
    required String messageBody,
    required String factText,
    required int visibility,
    List<RoomPendingUpload> uploads = const [],
  }) async {
    if (_rejectIfDiscussionReadOnly()) return false;
    try {
      await _case.pinFactFromComposer(
        beaconId: state.beacon.id,
        messageBody: messageBody,
        factText: factText,
        visibility: visibility,
        uploads: uploads,
      );
    } on BeaconFactPinAfterMessageException {
      _effects.emit(const ShowMessage(BeaconFactPinMessageKeptMessage()));
      return false;
    } on Object catch (e) {
      _showSnackError(e);
      return false;
    }
    await _refreshFactCards(state.beacon.id);
    _effects.emit(const ShowMessage(BeaconFactPinSuccessMessage()));
    return true;
  }

  Future<void> _fetchBeaconByIdWithTimeline({bool background = false}) async {
    try {
      final beaconId = state.beacon.id;
      final myUserId = state.myProfile.id;
      final wasForwardsLoaded = state.forwardsLoaded;
      // Background refreshes (catch-up / invalidation) must not clear loaded
      // context mid-fetch — author HUD CTAs gate on beaconContextLoaded and
      // would flicker off then on. Initial load still clears so room admission
      // waits for enrichment (see beacon_view_initial_load_test).
      final retainLoadedContext = background && state.beaconContextLoaded;

      late final Beacon beacon;
      try {
        beacon = await _fetchBeaconByIdOrRetry(beaconId);
      } on BeaconFetchException {
        if (isClosed) return;
        if (!state.beaconContentLoaded) {
          emit(
            state.copyWith(
              beaconContentLoaded: false,
              beaconContextLoaded: false,
              beaconUnavailable: true,
              status: const StateIsSuccess(),
            ),
          );
        } else if (!background) {
          _showSnackError(const BeaconFetchException());
        }
        return;
      }

      if (!isClosed) {
        emit(
          state.copyWith(
            beacon: beacon,
            beaconContentLoaded: true,
            beaconContextLoaded: retainLoadedContext,
            beaconUnavailable: false,
            status: StateStatus.isSuccess,
          ),
        );
      }

      // Involvement (offers / Plan activity) stays behind canReadInvolvement.
      // Room participants / room state / Chat-adjacent APIs are member/author only.
      // Null accessLevel (fixtures / local) keeps legacy full-fetch behavior.
      final skipInvolvement = !beacon.canReadInvolvement;
      final isMember = beacon.accessLevel?.isMember ?? true;
      final skipRoom = !isMember;
      final canReadAdmittedHelpers = beacon.canReadAdmittedHelpers;
      final results = await Future.wait([
        if (skipInvolvement)
          Future.value(const <
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
                  int stakeState,
                  int offerKind,
                  bool isDirectAuthorForward,
                })
              >[])
        else
          _case.fetchHelpOffersWithCoordination(
            beaconId: beaconId,
          ),
        _case.fetchInboxContextForBeacon(beaconId),
        _case.fetchFactCards(beaconId),
        if (skipRoom)
          Future.value(const <BeaconParticipant>[])
        else
          _case.fetchRoomParticipants(beaconId),
        if (skipRoom)
          Future<BeaconRoomState?>.value()
        else
          _case.fetchRoomStateIfAllowed(beaconId),
        if (skipRoom || skipInvolvement)
          Future.value(const <BeaconActivityEvent>[])
        else
          _case.fetchRoomActivityEvents(beaconId),
        _case.fetchDisplayStatus(beaconId),
        if (canReadAdmittedHelpers)
          _case.fetchAdmittedHelpers(beaconId)
        else
          Future.value(const <Profile>[]),
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
                  int stakeState,
                  int offerKind,
                  bool isDirectAuthorForward,
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
      final displayStatus = results[6] as BeaconDisplayStatusDto?;
      final admittedHelperRoster = results[7]! as List<Profile>;
      final openCoordinationBlocker = beaconRoomCue != null
          ? await _case.fetchOpenCoordinationBlocker(beaconId)
          : null;

      final isHelpOffered = helpOffers
          .where((c) => c.status == 0)
          .any((c) => c.userId == myUserId);

      final helpOffersList = timelineHelpOffersFromRemote(helpOffers);

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

      _hydratePinnedFactsSeen(beaconId, factCards);
      final clearForwards = skipRoom && wasForwardsLoaded;
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
          pinnedFactsSeenAt: _case.pinnedFactsSeenAt(beaconId, myUserId),
          roomParticipants: roomParticipants,
          roomParticipantsLoaded: !skipRoom,
          admittedHelperRoster: admittedHelperRoster,
          admittedHelpersLoaded: canReadAdmittedHelpers,
          beaconRoomCue: beaconRoomCue,
          openCoordinationBlocker: openCoordinationBlocker,
          roomActivityEvents: roomActivityEvents,
          showDraftEvaluationCta: showDraftEvaluationCta,
          reviewWindowInfo: reviewWindowInfo,
          displayStatus: displayStatus,
          forwardsLoaded: clearForwards ? false : wasForwardsLoaded,
          myForwards: clearForwards ? const [] : state.myForwards,
          viewerForwardEdges: clearForwards
              ? const []
              : state.viewerForwardEdges,
          forwardReasonSlugs: clearForwards
              ? const {}
              : state.forwardReasonSlugs,
          involvementHelpOfferedIds: clearForwards
              ? const {}
              : state.involvementHelpOfferedIds,
          involvementWatchingIds: clearForwards
              ? const {}
              : state.involvementWatchingIds,
          involvementOnwardForwarderIds: clearForwards
              ? const {}
              : state.involvementOnwardForwarderIds,
          involvementRejectedIds: clearForwards
              ? const {}
              : state.involvementRejectedIds,
          beaconContentLoaded: true,
          beaconContextLoaded: true,
          beaconUnavailable: false,
          loadError: null,
          status: StateStatus.isSuccess,
        ),
      );
      if (!skipRoom && wasForwardsLoaded) {
        unawaited(_refreshForwards(beaconId, myUserId));
      }
    } catch (e) {
      if (isClosed) return;
      if (!state.beaconContentLoaded) {
        emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      } else if (!background) {
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
    final isMember = state.beacon.accessLevel?.isMember ?? true;
    if (!isMember || state.forwardsLoaded || state.forwardsLoading) return;
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

  Set<String> _visiblePeopleIds() => {
    state.beacon.author.id,
    for (final offer in state.helpOffers) offer.user.id,
    for (final participant in state.roomParticipants) participant.userId,
    for (final helper in state.admittedHelperRoster) helper.id,
    for (final edge in state.viewerForwardEdges) ...{
      edge.sender.id,
      edge.recipient.id,
    },
    for (final edge in state.myForwards) ...{
      edge.sender.id,
      edge.recipient.id,
    },
  }..removeWhere((id) => id.isEmpty);

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
    int stakeState,
    int offerKind,
    bool isDirectAuthorForward,
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
