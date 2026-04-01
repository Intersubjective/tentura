import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'evaluation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'evaluation_state.dart';

class EvaluationCubit extends Cubit<EvaluationState> {
  EvaluationCubit(
    this._repository, {
    required String beaconId,
    String beaconTitle = '',
  }) : super(
         EvaluationState(
           beaconId: beaconId,
           beaconTitle: beaconTitle,
         ),
       );

  factory EvaluationCubit.fromGetIt({
    required String beaconId,
    String beaconTitle = '',
  }) =>
      EvaluationCubit(
        GetIt.I<EvaluationRepository>(),
        beaconId: beaconId,
        beaconTitle: beaconTitle,
      );

  final EvaluationRepository _repository;

  Future<void> loadAll() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final window = await _repository.fetchReviewWindowStatus(state.beaconId);
      final participants = window.hasWindow
          ? await _repository.fetchParticipants(state.beaconId)
          : <EvaluationParticipant>[];
      EvaluationSummary? summary;
      if (window.windowComplete ?? false) {
        summary = await _repository.fetchSummary(state.beaconId);
      }
      emit(
        state.copyWith(
          windowInfo: window,
          participants: participants,
          summary: summary,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> loadParticipantsOnly() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final participants = await _repository.fetchParticipants(state.beaconId);
      final window = await _repository.fetchReviewWindowStatus(state.beaconId);
      emit(
        state.copyWith(
          participants: participants,
          windowInfo: window,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> submitOne({
    required String evaluatedUserId,
    required EvaluationValue value,
    required List<String> reasonTags,
    String note = '',
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _repository.submit(
        beaconId: state.beaconId,
        evaluatedUserId: evaluatedUserId,
        value: value.wire,
        reasonTags: reasonTags,
        note: note,
      );
      final participants = await _repository.fetchParticipants(state.beaconId);
      final window = await _repository.fetchReviewWindowStatus(state.beaconId);
      emit(
        state.copyWith(
          participants: participants,
          windowInfo: window,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> finalize() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _repository.finalize(state.beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> skip() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _repository.skip(state.beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
