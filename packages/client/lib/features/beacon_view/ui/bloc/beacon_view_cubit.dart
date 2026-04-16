import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

import '../../data/repository/beacon_view_repository.dart';
import '../../data/repository/coordination_repository.dart';
import '../message/commitment_messages.dart';
import 'beacon_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'beacon_view_state.dart';

class BeaconViewCubit extends Cubit<BeaconViewState> {
  BeaconViewCubit({
    required String id,
    required Profile myProfile,
    BeaconRepository? beaconRepository,
    BeaconViewRepository? beaconViewRepository,
    ForwardRepository? forwardRepository,
    EvaluationRepository? evaluationRepository,
    CoordinationRepository? coordinationRepository,
    InboxRepository? inboxRepository,
  }) : _beaconViewRepository =
           beaconViewRepository ?? GetIt.I<BeaconViewRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       _evaluationRepository =
           evaluationRepository ?? GetIt.I<EvaluationRepository>(),
       _coordinationRepository =
           coordinationRepository ?? GetIt.I<CoordinationRepository>(),
       _inboxRepository = inboxRepository ?? GetIt.I<InboxRepository>(),
       super(_idToState(id, myProfile)) {
    _forwardCompletedSub = _forwardRepository.forwardCompleted.listen(
      (beaconId) {
        if (!isClosed && beaconId == state.beacon.id) {
          unawaited(_fetchBeaconByIdWithTimeline());
        }
      },
      cancelOnError: false,
    );
    _commitmentChangesSub = _forwardRepository.commitmentChanges.listen(
      (CommitmentEvent event) {
        if (!isClosed && event.beaconId == state.beacon.id) {
          unawaited(_fetchBeaconByIdWithTimeline());
        }
      },
      cancelOnError: false,
    );
    unawaited(
      state.hasFocusedComment
          ? _fetchBeaconByCommentId()
          : _fetchBeaconByIdWithTimeline(),
    );
  }

  final BeaconRepository _beaconRepository;
  final BeaconViewRepository _beaconViewRepository;
  final ForwardRepository _forwardRepository;

  final EvaluationRepository _evaluationRepository;

  final CoordinationRepository _coordinationRepository;

  final InboxRepository _inboxRepository;

  late final StreamSubscription<String> _forwardCompletedSub;

  late final StreamSubscription<CommitmentEvent> _commitmentChangesSub;

  @override
  Future<void> close() async {
    await _forwardCompletedSub.cancel();
    await _commitmentChangesSub.cancel();
    return super.close();
  }

  Future<void> moveToWatching() async {
    if (state.inboxStatus != InboxItemStatus.needsMe) return;
    try {
      await _inboxRepository.setStatus(
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
      await _inboxRepository.setStatus(
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
      await _inboxRepository.setStatus(
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
      await _inboxRepository.setStatus(
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
      await _beaconRepository.delete(beaconId);
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
        await _evaluationRepository.beaconCloseWithReview(state.beacon.id);
      } else {
        await _beaconRepository.setBeaconLifecycle(next, id: state.beacon.id);
      }
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> commit({
    required String message,
    String? helpType,
  }) async {
    final wasAlreadyCommitted = state.isCommitted;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _forwardRepository.commit(
        beaconId: state.beacon.id,
        message: message,
        helpType: helpType,
        notifyCommitmentListeners: !wasAlreadyCommitted,
      );
      await _fetchBeaconByIdWithTimeline();
      if (!state.hasError && !wasAlreadyCommitted) {
        emit(
          state.copyWith(
            status: StateIsMessaging(const MovedToMyWorkMessage()),
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
      await _forwardRepository.withdraw(
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
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _coordinationRepository.setCoordinationResponse(
        beaconId: state.beacon.id,
        commitUserId: commitUserId,
        responseType: responseType,
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
      await _coordinationRepository.setBeaconCoordinationStatus(
        beaconId: state.beacon.id,
        coordinationStatus: status.smallintValue,
      );
      await _fetchBeaconByIdWithTimeline();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _fetchBeaconByIdWithTimeline() async {
    try {
      final beaconId = state.beacon.id;
      final myUserId = state.myProfile.id;

      final results = await Future.wait([
        _beaconRepository.fetchBeaconById(beaconId),
        _coordinationRepository.fetchCommitmentsWithCoordination(
          beaconId: beaconId,
        ),
        _forwardRepository.fetchUpdates(beaconId: beaconId),
        _inboxRepository.fetchInboxContextForBeacon(beaconId),
        _forwardRepository.fetchMyForwardEdges(
          beaconId: beaconId,
          myUserId: myUserId,
        ),
        _forwardRepository.fetchBeaconInvolvement(beaconId: beaconId),
      ]);

      final beacon = results[0] as Beacon;
      final commitments =
          results[1]
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
                })
              >;
      final updates =
          results[2]
              as List<({Profile author, String content, DateTime createdAt})>;
      final inboxCtx =
          results[3]
              as ({
                InboxItemStatus? status,
                InboxProvenance provenance,
                String latestNotePreview,
              });
      final myForwards = results[4] as List<ForwardEdge>;
      final involvement = results[5] as BeaconInvolvementData;

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
            author: u.author,
            content: u.content,
            createdAt: u.createdAt,
          ),
        TimelineCreation(author: beacon.author, createdAt: beacon.createdAt),
      ]..sort();

      emit(
        state.copyWith(
          beacon: beacon,
          timeline: timeline,
          commitments: commitmentsList,
          isCommitted: isCommitted,
          inboxStatus: inboxCtx.status,
          forwardProvenance: inboxCtx.provenance,
          inboxLatestNotePreview: inboxCtx.latestNotePreview,
          myForwards: myForwards,
          involvementCommittedIds: involvement.committedIds,
          involvementWatchingIds: involvement.watchingIds,
          involvementOnwardForwarderIds: involvement.onwardForwarderIds,
          involvementRejectedIds: involvement.rejectedIds,
          hasForwardedThisBeaconOnce: myForwards.isNotEmpty,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _fetchBeaconByCommentId() async {
    try {
      final (:beacon, comment: _) = await _beaconViewRepository
          .fetchBeaconByCommentId(state.focusCommentId);
      final hasForwardedThisBeaconOnce = await _forwardRepository
          .currentUserHasForwardedBeacon(beacon.id);
      final inboxCtx = await _inboxRepository.fetchInboxContextForBeacon(
        beacon.id,
      );
      emit(
        state.copyWith(
          beacon: beacon,
          hasForwardedThisBeaconOnce: hasForwardedThisBeaconOnce,
          inboxStatus: inboxCtx.status,
          forwardProvenance: inboxCtx.provenance,
          inboxLatestNotePreview: inboxCtx.latestNotePreview,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
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
        _ when id.startsWith('C') => BeaconViewState(
          beacon: _emptyBeacon,
          focusCommentId: id,
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
  }) row,
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
    events.add(
      TimelineCommitmentWithdrawn(
        committer: row.user,
        message: row.message,
        withdrawnAt: row.updatedAt,
        uncommitReason: row.uncommitReason,
      ),
    );
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
  final edited =
      row.updatedAt.difference(row.createdAt).inSeconds.abs() > 1;
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
