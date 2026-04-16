import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'evaluation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'evaluation_state.dart';

class EvaluationCubit extends Cubit<EvaluationState> {
  EvaluationCubit(
    this._evaluationCase, {
    required String beaconId,
    String beaconTitle = '',
    bool isDraftMode = false,
  }) : super(
         EvaluationState(
           beaconId: beaconId,
           beaconTitle: beaconTitle,
           isDraftMode: isDraftMode,
         ),
       );

  factory EvaluationCubit.fromGetIt({
    required String beaconId,
    String beaconTitle = '',
    bool isDraftMode = false,
  }) =>
      EvaluationCubit(
        GetIt.I<EvaluationCase>(),
        beaconId: beaconId,
        beaconTitle: beaconTitle,
        isDraftMode: isDraftMode,
      );

  final EvaluationCase _evaluationCase;

  Future<void> loadAll() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final window = await _evaluationCase.fetchReviewWindowStatus(state.beaconId);
      final participants = window.hasWindow
          ? await _evaluationCase.fetchParticipants(state.beaconId)
          : <EvaluationParticipant>[];
      EvaluationSummary? summary;
      if (window.windowComplete) {
        summary = await _evaluationCase.fetchSummary(state.beaconId);
      }
      emit(
        state.copyWith(
          windowInfo: window,
          beaconTitle: window.beaconTitle,
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
      if (state.isDraftMode) {
        final data = await _evaluationCase.fetchDraftModeBootstrap(state.beaconId);
        emit(
          state.copyWith(
            participants: data.participants,
            beaconTitle: data.window.beaconTitle,
            status: StateStatus.isSuccess,
          ),
        );
        return;
      }
      final participants = await _evaluationCase.fetchParticipants(state.beaconId);
      final window = await _evaluationCase.fetchReviewWindowStatus(state.beaconId);
      emit(
        state.copyWith(
          participants: participants,
          windowInfo: window,
          beaconTitle: window.beaconTitle,
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
      if (state.isDraftMode) {
        await _evaluationCase.draftSave(
          beaconId: state.beaconId,
          evaluatedUserId: evaluatedUserId,
          value: value.wire,
          reasonTags: reasonTags,
          note: note,
        );
        final participants =
            await _evaluationCase.fetchDraftParticipants(state.beaconId);
        emit(
          state.copyWith(
            participants: participants,
            status: StateStatus.isSuccess,
          ),
        );
        return;
      }
      await _evaluationCase.submit(
        beaconId: state.beaconId,
        evaluatedUserId: evaluatedUserId,
        value: value.wire,
        reasonTags: reasonTags,
        note: note,
      );
      final participants = await _evaluationCase.fetchParticipants(state.beaconId);
      final window = await _evaluationCase.fetchReviewWindowStatus(state.beaconId);
      emit(
        state.copyWith(
          participants: participants,
          windowInfo: window,
          beaconTitle: window.beaconTitle,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> finalize() async {
    if (state.isDraftMode) {
      emit(state.copyWith(status: StateIsNavigating.back));
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _evaluationCase.finalize(state.beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> skip() async {
    if (state.isDraftMode) {
      emit(state.copyWith(status: StateIsNavigating.back));
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _evaluationCase.skip(state.beaconId);
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
