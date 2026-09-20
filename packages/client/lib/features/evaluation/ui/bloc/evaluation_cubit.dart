import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_summary.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/evaluation_exception.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'evaluation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'evaluation_state.dart';

class EvaluationCubit extends Cubit<EvaluationState> {
  EvaluationCubit(
    this._evaluationCase, {
    required String beaconId,
    String beaconTitle = '',
    bool isDraftMode = false,
    UiEffectPort? effects,
  }) : _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
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
  }) => EvaluationCubit(
    GetIt.I<EvaluationCase>(),
    beaconId: beaconId,
    beaconTitle: beaconTitle,
    isDraftMode: isDraftMode,
  );

  final EvaluationCase _evaluationCase;

  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: StateStatus.isSuccess));
    }
  }

  void _emitNavigateBack() {
    _effects.emit(const NavigateBack());
    if (!isClosed) {
      emit(state.copyWith(status: StateStatus.isSuccess));
    }
  }

  /// Emits [window] with lifecycle flags derived from it.
  ///
  /// `ReviewWindowInfo` carries no beacon lifecycle, so the flags come from
  /// the window read. A missing window only means "paused" right after a
  /// lifecycle error for a viewer who had a package ([afterLifecycleError]).
  EvaluationState _withWindow(
    EvaluationState base,
    ReviewWindowInfo window, {
    bool afterLifecycleError = false,
  }) {
    if (window.windowComplete) {
      return base.copyWith(
        windowInfo: window,
        beaconIsClosed: true,
        beaconIsInReview: false,
      );
    }
    if (window.hasWindow) {
      return base.copyWith(
        windowInfo: window,
        beaconIsClosed: false,
        beaconIsInReview: true,
      );
    }
    return base.copyWith(
      windowInfo: window,
      beaconIsClosed: false,
      beaconIsInReview: !(afterLifecycleError && base.participants.isNotEmpty),
    );
  }

  /// 1401 and 1405 are ambiguous (D12): the server raises them after a reopen
  /// and after a final close. Re-read the window once to tell them apart.
  Future<void> _classifyLifecycleError(Object originalError) async {
    try {
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return;
      emit(
        _withWindow(
          state,
          window,
          afterLifecycleError: true,
        ).copyWith(reviewContentLoaded: true, status: StateStatus.isSuccess),
      );
    } catch (_) {
      // The classifying read failed: keep what we had and report normally.
      if (!isClosed) _emitSnackError(originalError);
    }
  }

  Future<void> _onError(Object e) async {
    if (!state.isDraftMode &&
        (e is EvaluationReviewWindowNotOpenException ||
            e is EvaluationReviewWindowExpiredException)) {
      await _classifyLifecycleError(e);
    } else {
      _emitSnackError(e);
    }
  }

  Future<void> loadAll() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return;
      final participants = window.hasWindow
          ? await _evaluationCase.fetchParticipants(state.beaconId)
          : <EvaluationParticipant>[];
      if (isClosed) return;
      EvaluationSummary? summary;
      if (window.windowComplete) {
        summary = await _evaluationCase.fetchSummary(state.beaconId);
        if (isClosed) return;
      }
      emit(
        _withWindow(state, window).copyWith(
          beaconTitle: window.beaconTitle,
          participants: participants,
          summary: summary,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      _emitSnackError(e);
    }
  }

  Future<void> loadParticipantsOnly() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      if (state.isDraftMode) {
        final data = await _evaluationCase.fetchDraftModeBootstrap(
          state.beaconId,
        );
        if (isClosed) return;
        emit(
          state.copyWith(
            participants: data.participants,
            beaconTitle: data.window.beaconTitle,
            reviewContentLoaded: true,
            status: StateStatus.isSuccess,
          ),
        );
        return;
      }
      final participants = await _evaluationCase.fetchParticipants(
        state.beaconId,
      );
      if (isClosed) return;
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return;
      emit(
        _withWindow(
          state.copyWith(participants: participants),
          window,
        ).copyWith(
          beaconTitle: window.beaconTitle,
          reviewContentLoaded: true,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      await _onError(e);
    }
  }

  Future<bool> submitOne({
    required String evaluatedUserId,
    required EvaluationValue value,
    String note = '',
    List<String>? acknowledgedHelpTags,
  }) async {
    if (state.isLoading) {
      return false;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final effectiveNote = value == EvaluationValue.noBasis ? '' : note;
      if (state.isDraftMode) {
        await _evaluationCase.draftSave(
          beaconId: state.beaconId,
          evaluatedUserId: evaluatedUserId,
          value: value.wire,
          reasonTags: null,
          note: effectiveNote,
        );
        if (isClosed) return true;
        final participants = await _evaluationCase.fetchDraftParticipants(
          state.beaconId,
        );
        if (isClosed) return true;
        emit(
          state.copyWith(
            participants: participants,
            status: StateStatus.isSuccess,
          ),
        );
        return true;
      }
      await _evaluationCase.submit(
        beaconId: state.beaconId,
        evaluatedUserId: evaluatedUserId,
        value: value.wire,
        reasonTags: null,
        note: effectiveNote,
        acknowledgedHelpTags: value == EvaluationValue.noBasis
            ? const <String>[]
            : acknowledgedHelpTags,
      );
      if (isClosed) return true;
      final participants = await _evaluationCase.fetchParticipants(
        state.beaconId,
      );
      if (isClosed) return true;
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return true;
      emit(
        _withWindow(
          state.copyWith(participants: participants),
          window,
        ).copyWith(
          beaconTitle: window.beaconTitle,
          reviewContentLoaded: true,
          status: StateStatus.isSuccess,
        ),
      );
      return true;
    } catch (e) {
      if (isClosed) return false;
      await _onError(e);
      return false;
    }
  }

  Future<bool> clearOne({required String evaluatedUserId}) async {
    if (state.isLoading) {
      return false;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _evaluationCase.draftDelete(
        beaconId: state.beaconId,
        evaluatedUserId: evaluatedUserId,
      );
      if (isClosed) return true;
      if (state.isDraftMode) {
        final participants = await _evaluationCase.fetchDraftParticipants(
          state.beaconId,
        );
        if (isClosed) return true;
        emit(
          state.copyWith(
            participants: participants,
            status: StateStatus.isSuccess,
          ),
        );
      } else {
        final participants = await _evaluationCase.fetchParticipants(
          state.beaconId,
        );
        if (isClosed) return true;
        final window = await _evaluationCase.fetchReviewWindowStatus(
          state.beaconId,
        );
        if (isClosed) return true;
        emit(
          _withWindow(
            state.copyWith(participants: participants),
            window,
          ).copyWith(
            beaconTitle: window.beaconTitle,
            status: StateStatus.isSuccess,
          ),
        );
      }
      return true;
    } catch (e) {
      if (isClosed) return false;
      await _onError(e);
      return false;
    }
  }

  Future<void> finalize() async {
    if (state.isDraftMode) {
      // Draft mode has no package to stay with: the sheet is the whole flow.
      _emitNavigateBack();
      return;
    }
    if (!state.canFinalize) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _evaluationCase.finalize(state.beaconId);
      if (isClosed) return;
      await _refreshAfterSend();
    } catch (e) {
      if (isClosed) return;
      await _onError(e);
    }
  }

  /// Re-reads the package after a send that already succeeded (#162).
  ///
  /// A failure here is a read failure, never a send failure: the UI must not
  /// fall back to the pre-send state. Keep the participants we have, mark the
  /// window sent locally, and surface the read failure as a snackbar.
  Future<void> _refreshAfterSend() async {
    try {
      final participants = await _evaluationCase.fetchParticipants(
        state.beaconId,
      );
      if (isClosed) return;
      final window = await _evaluationCase.fetchReviewWindowStatus(
        state.beaconId,
      );
      if (isClosed) return;
      emit(
        _withWindow(
          state.copyWith(participants: participants),
          window,
        ).copyWith(
          beaconTitle: window.beaconTitle,
          reviewContentLoaded: true,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      final window = state.windowInfo;
      if (window != null) {
        emit(
          state.copyWith(
            windowInfo: window.copyWith(
              userReviewStatus: 2,
              sentAt: window.sentAt ?? DateTime.now().toUtc(),
            ),
            status: StateStatus.isSuccess,
          ),
        );
      }
      await _onError(e);
    }
  }
}
