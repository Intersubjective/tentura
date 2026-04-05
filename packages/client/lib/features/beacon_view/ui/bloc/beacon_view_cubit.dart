import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';

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
  }) : _beaconViewRepository =
           beaconViewRepository ?? GetIt.I<BeaconViewRepository>(),
       _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       _evaluationRepository =
           evaluationRepository ?? GetIt.I<EvaluationRepository>(),
       _coordinationRepository =
           coordinationRepository ?? GetIt.I<CoordinationRepository>(),
       super(_idToState(id, myProfile)) {
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

  Future<void> setBeaconCoordinationStatus(BeaconCoordinationStatus status) async {
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
        _forwardRepository.fetchEdges(beaconId: beaconId),
        _coordinationRepository.fetchCommitmentsWithCoordination(
          beaconId: beaconId,
        ),
        _forwardRepository.fetchUpdates(beaconId: beaconId),
      ]);

      final beacon = results[0] as Beacon;
      final forwardEdges = results[1] as List<ForwardEdge>;
      final commitments = results[2] as List<
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
          })>;
      final updates = results[3]
          as List<({Profile author, String content, DateTime createdAt})>;

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
            coordinationResponse:
                CoordinationResponseType.tryFromInt(c.responseType),
            uncommitReason: c.uncommitReason,
          ),
      ];

      final timeline = <TimelineEntry>[
        for (final edge in forwardEdges) TimelineForward(edge),
        ...commitmentsList,
        for (final u in updates)
          TimelineUpdate(
            author: u.author,
            content: u.content,
            createdAt: u.createdAt,
          ),
      ]..sort();

      emit(
        state.copyWith(
          beacon: beacon,
          forwardEdges: forwardEdges,
          timeline: timeline,
          commitments: commitmentsList,
          isCommitted: isCommitted,
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
      emit(
        state.copyWith(
          beacon: beacon,
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
