import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart'
    show BeaconInvolvementData;
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

import '../../domain/use_case/beacon_view_case.dart';
import '../message/beacon_update_messages.dart';
import '../message/commitment_messages.dart';
import 'beacon_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_view_state.dart';

class BeaconViewCubit extends Cubit<BeaconViewState> {
  BeaconViewCubit({
    required String id,
    required Profile myProfile,
    BeaconViewCase? beaconViewCase,
  }) : _case = beaconViewCase ?? GetIt.I<BeaconViewCase>(),
       super(_idToState(id, myProfile)) {
    _forwardCompletedSub = _case.forwardCompleted.listen(
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
    _commitmentChangesSub = _case.commitmentChanges.listen(
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
    unawaited(_fetchBeaconByIdWithTimeline());
  }

  final BeaconViewCase _case;

  late final StreamSubscription<String> _forwardCompletedSub;

  late final StreamSubscription<CommitmentEvent> _commitmentChangesSub;

  late final StreamSubscription<BeaconRoomInvalidation> _beaconRoomRefreshSub;

  bool _fetchInProgress = false;
  bool _fetchPending = false;

  final Set<BeaconRoomEntityType> _pendingRoomTypes = {};

  @override
  Future<void> close() async {
    await _forwardCompletedSub.cancel();
    await _commitmentChangesSub.cancel();
    await _beaconRoomRefreshSub.cancel();
    return super.close();
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
      emit(state.copyWith(status: StateHasError(e)));
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
      emit(state.copyWith(status: StateHasError(e)));
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
      emit(state.copyWith(status: StateHasError(e)));
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
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> delete(String beaconId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.deleteBeacon(beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> toggleLifecycle() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final next = state.beacon.isListed
          ? BeaconLifecycle.closed
          : BeaconLifecycle.open;
      if (state.isBeaconMine &&
          next == BeaconLifecycle.closed &&
          state.beacon.lifecycle == BeaconLifecycle.open) {
        await _case.beaconCloseWithReview(state.beacon.id);
      } else {
        await _case.setBeaconLifecycle(next, id: state.beacon.id);
      }
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> commit({
    required String message,
    List<String>? helpTypes,
  }) async {
    final wasAlreadyCommitted = state.isCommitted;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.forwardCommit(
        beaconId: state.beacon.id,
        message: message,
        helpTypes: helpTypes,
        notifyCommitmentListeners: !wasAlreadyCommitted,
      );
      await _fetchBeaconByIdWithTimeline();
      if (!state.hasError && !wasAlreadyCommitted) {
        emit(
          state.copyWith(
            status: StateIsMessaging(
              CommittedForwardNudgeMessage(state.beacon.id),
            ),
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> withdraw({
    required String message,
    required String uncommitReason,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.forwardWithdraw(
        beaconId: state.beacon.id,
        message: message,
        uncommitReason: uncommitReason,
      );
      await _fetchBeaconByIdWithTimeline();
      if (!state.hasError) {
        emit(
          state.copyWith(
            status: StateIsMessaging(const MovedToInboxMessage()),
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> setCoordinationResponse({
    required String commitUserId,
    required int responseType,
    required bool inviteToRoom,
    required bool removeFromRoom,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.setCoordinationResponse(
        beaconId: state.beacon.id,
        commitUserId: commitUserId,
        responseType: responseType,
        inviteToRoom: inviteToRoom,
        removeFromRoom: removeFromRoom,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
      rethrow;
    }
  }

  Future<void> updatePublicStatus(
    int publicStatus, {
    String? lastPublicMeaningfulChange,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.updatePublicStatus(
        beaconId: state.beacon.id,
        publicStatus: publicStatus,
        lastPublicMeaningfulChange: lastPublicMeaningfulChange,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> setBeaconCoordinationStatus(
    BeaconCoordinationStatus status,
  ) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _case.setBeaconCoordinationStatus(
        beaconId: state.beacon.id,
        coordinationStatus: status.smallintValue,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  /// Immediately zeros out the cached unread count.
  ///
  /// Call this when the user leaves the room surface so the badge clears
  /// without waiting for the next server invalidation.
  void clearRoomUnread() {
    if (!isClosed && state.roomUnreadCount != 0) {
      emit(state.copyWith(roomUnreadCount: 0));
    }
  }

  /// Run one stream-triggered full refresh under the concurrency gate.
  ///
  /// At most one gate-guarded fetch runs at a time. If a second invalidation
  /// arrives while one is in flight, the flag is set and a follow-up fetch
  /// starts once the current one finishes. Explicit callers (commit, withdraw,
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
      if (!isClosed) emit(state.copyWith(status: StateHasError(e)));
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
    var needRoomState = false;
    var needFactCards = false;
    for (final t in types) {
      if (t == BeaconRoomEntityType.roomMessage) {
        needActivity = true;
        needUnread = true;
      } else if (t == BeaconRoomEntityType.activityEvent) {
        needActivity = true;
      } else if (t == BeaconRoomEntityType.participant) {
        needParticipants = true;
        needRoomState = true;
      } else if (t == BeaconRoomEntityType.factCard) {
        needFactCards = true;
      } else if (t == BeaconRoomEntityType.blocker) {
        needRoomState = true;
      }
    }
    await Future.wait([
      if (needActivity) _refreshRoomActivityEvents(beaconId),
      if (needUnread) _refreshRoomUnread(beaconId),
      if (needParticipants) _refreshRoomParticipants(beaconId),
      if (needRoomState) _refreshBeaconRoomCue(beaconId),
      if (needFactCards) _refreshFactCards(beaconId),
    ]);
  }

  Future<void> _refreshRoomActivityEvents(String beaconId) async {
    final events = await _case.fetchRoomActivityEvents(beaconId);
    if (!isClosed) emit(state.copyWith(roomActivityEvents: events));
  }

  Future<void> _refreshRoomUnread(String beaconId) async {
    final count = await _case.fetchRoomUnreadForBeacon(beaconId);
    if (!isClosed) emit(state.copyWith(roomUnreadCount: count));
  }

  Future<void> _refreshRoomParticipants(String beaconId) async {
    final participants = await _case.fetchRoomParticipants(beaconId);
    if (!isClosed) emit(state.copyWith(roomParticipants: participants));
  }

  Future<void> _refreshBeaconRoomCue(String beaconId) async {
    final cue = await _case.fetchRoomStateIfAllowed(beaconId);
    if (!isClosed) emit(state.copyWith(beaconRoomCue: cue));
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

      final results = await Future.wait([
        _case.fetchBeaconById(beaconId),
        _case.fetchCommitmentsWithCoordination(
          beaconId: beaconId,
        ),
        _case.fetchBeaconUpdates(beaconId: beaconId),
        _case.fetchInboxContextForBeacon(beaconId),
        _case.fetchFactCards(beaconId),
        _case.fetchRoomParticipants(beaconId),
        _case.fetchRoomStateIfAllowed(beaconId),
        _case.fetchRoomActivityEvents(beaconId),
        _case.fetchRoomUnreadForBeacon(beaconId),
      ]);

      final beacon = results[0]! as Beacon;
      final commitments =
          results[1]!
              as List<
                ({
                  String beaconId,
                  String userId,
                  Profile user,
                  String message,
                  String? helpType,
                  int status,
                  String? uncommitReason,
                  DateTime createdAt,
                  DateTime updatedAt,
                  int? responseType,
                  DateTime? responseUpdatedAt,
                  String? responseAuthorUserId,
                  int? roomAccess,
                })
              >;
      final updates =
          results[2]!
              as List<
                ({
                  String id,
                  int number,
                  Profile author,
                  String content,
                  DateTime createdAt,
                })
              >;
      final inboxCtx =
          results[3]!
              as ({
                InboxItemStatus? status,
                InboxProvenance provenance,
                String latestNotePreview,
              });
      final factCards = results[4]! as List<BeaconFactCard>;
      final roomParticipants = results[5]! as List<BeaconParticipant>;
      final beaconRoomCue = results[6] as BeaconRoomState?;
      final roomActivityEvents = results[7]! as List<BeaconActivityEvent>;
      final roomUnreadCount = results[8]! as int;

      final isCommitted = commitments
          .where((c) => c.status == 0)
          .any((c) => c.userId == myUserId);

      final commitmentsList = <TimelineCommitment>[
        for (final c in commitments)
          TimelineCommitment(
            user: c.user,
            message: c.message,
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
            isWithdrawn: c.status == 1,
            helpType: c.helpType,
            coordinationResponse: CoordinationResponseType.tryFromInt(
              c.responseType,
            ),
            uncommitReason: c.uncommitReason,
            roomAccess: c.roomAccess,
          ),
      ];

      final commitmentTimeline = <TimelineEntry>[
        for (final c in commitments)
          ...commitmentRowsToTimelineEntries(beacon: beacon, row: c),
      ];

      final timeline = <TimelineEntry>[
        ...commitmentTimeline,
        if (beacon.coordinationStatusUpdatedAt != null)
          TimelineBeaconCoordinationStatusChanged(
            author: beacon.author,
            status: beacon.coordinationStatus,
            at: beacon.coordinationStatusUpdatedAt!,
          ),
        if (beacon.lifecycle != BeaconLifecycle.open &&
            beacon.updatedAt != beacon.createdAt)
          TimelineBeaconLifecycleChanged(
            author: beacon.author,
            lifecycle: beacon.lifecycle,
            at: beacon.updatedAt,
          ),
        for (final u in updates)
          TimelineUpdate(
            id: u.id,
            number: u.number,
            author: u.author,
            content: u.content,
            createdAt: u.createdAt,
          ),
        TimelineCreation(author: beacon.author, createdAt: beacon.createdAt),
      ]..sort();

      var showDraftEvaluationCta = false;
      if (beacon.lifecycle == BeaconLifecycle.open) {
        try {
          showDraftEvaluationCta = await _case.beaconHasDraftEvaluationTargets(
            beaconId,
          );
        } on Object catch (_) {
          showDraftEvaluationCta = false;
        }
      }

      emit(
        state.copyWith(
          beacon: beacon,
          timeline: timeline,
          commitments: commitmentsList,
          isCommitted: isCommitted,
          inboxStatus: inboxCtx.status,
          forwardProvenance: inboxCtx.provenance,
          inboxLatestNotePreview: inboxCtx.latestNotePreview,
          factCards: factCards,
          roomParticipants: roomParticipants,
          beaconRoomCue: beaconRoomCue,
          roomActivityEvents: roomActivityEvents,
          showDraftEvaluationCta: showDraftEvaluationCta,
          roomUnreadCount: roomUnreadCount,
          forwardsLoaded: wasForwardsLoaded,
          status: StateStatus.isSuccess,
        ),
      );
      if (wasForwardsLoaded) {
        unawaited(_refreshForwards(beaconId, myUserId));
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
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
            status: StateHasError(e),
          ),
        );
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
          involvementCommittedIds: involvement.committedIds,
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

  Future<void> postAuthorUpdate(String content) async {
    try {
      await _case.postBeaconAuthorUpdate(
        beaconId: state.beacon.id,
        content: content,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> editAuthorUpdate({
    required String id,
    required String content,
  }) async {
    try {
      await _case.editBeaconAuthorUpdate(id: id, content: content);
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      if (e.toString().contains('Update edit window has expired')) {
        emit(
          state.copyWith(
            status: StateIsMessaging(const BeaconUpdateEditExpiredMessage()),
          ),
        );
      } else {
        emit(state.copyWith(status: StateHasError(e)));
      }
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
          status: StateHasError('Wrong id: $id'),
        ),
      };
}

/// One commitment row → ordered timeline events (commit / author response / edit / withdraw).
List<TimelineEntry> commitmentRowsToTimelineEntries({
  required Beacon beacon,
  required ({
    String beaconId,
    String userId,
    Profile user,
    String message,
    String? helpType,
    int status,
    String? uncommitReason,
    DateTime createdAt,
    DateTime updatedAt,
    int? responseType,
    DateTime? responseUpdatedAt,
    String? responseAuthorUserId,
    int? roomAccess,
  })
  row,
}) {
  final author = beacon.author;
  final response = CoordinationResponseType.tryFromInt(row.responseType);
  final events = <TimelineEntry>[];

  if (row.status == 1) {
    events.add(
      TimelineCommitmentCreated(
        committer: row.user,
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
          committer: row.user,
          response: response,
          at: row.responseUpdatedAt!,
        ),
      );
    }
    events
      ..add(
        TimelineCommitmentWithdrawn(
          committer: row.user,
          message: row.message,
          withdrawnAt: row.updatedAt,
          uncommitReason: row.uncommitReason,
        ),
      )
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  events.add(
    TimelineCommitmentCreated(
      committer: row.user,
      message: row.message,
      createdAt: row.createdAt,
      helpType: row.helpType,
    ),
  );
  if (response != null && row.responseUpdatedAt != null) {
    events.add(
      TimelineAuthorCoordinationResponse(
        author: author,
        committer: row.user,
        response: response,
        at: row.responseUpdatedAt!,
      ),
    );
  }
  final edited = row.updatedAt.difference(row.createdAt).inSeconds.abs() > 1;
  if (edited) {
    events.add(
      TimelineCommitmentUpdated(
        committer: row.user,
        message: row.message,
        updatedAt: row.updatedAt,
        helpType: row.helpType,
      ),
    );
  }
  events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return events;
}
