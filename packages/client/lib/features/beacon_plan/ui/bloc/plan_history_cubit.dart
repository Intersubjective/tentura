import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/beacon_plan_case.dart';
import 'plan_history_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'plan_history_state.dart';

/// Plan revision history with preview and «Вернуть эту версию».
///
/// The restore base is the newest revision as last loaded and moves forward
/// after every restore (never fixed at open).
class PlanHistoryCubit extends Cubit<PlanHistoryState> {
  PlanHistoryCubit({required this.beaconId, BeaconPlanCase? planCase})
    : _case = planCase ?? GetIt.I<BeaconPlanCase>(),
      super(const PlanHistoryState());

  final String beaconId;

  final BeaconPlanCase _case;

  Future<void> load() async {
    emit(state.copyWith(status: const StateIsLoading(), loadError: null));
    try {
      final page = await _case.revisions(beaconId);
      if (isClosed) return;
      emit(
        state.copyWith(
          items: page.items,
          names: page.names,
          nextBeforeSeq: page.nextBeforeSeq,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: const StateIsSuccess(), loadError: e));
    }
  }

  Future<void> loadMore() async {
    final before = state.nextBeforeSeq;
    if (before == null) return;
    try {
      final page = await _case.revisions(beaconId, beforeSeq: before);
      if (isClosed) return;
      emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          names: {...state.names, ...page.names},
          nextBeforeSeq: page.nextBeforeSeq,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      _emitError(e);
    }
  }

  Future<void> openPreview(int seq) async {
    emit(state.copyWith(previewSeq: seq, preview: null));
    try {
      final snapshot = await _case.revision(beaconId, seq);
      if (isClosed || state.previewSeq != seq) return;
      emit(state.copyWith(preview: snapshot));
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(previewSeq: null));
      _emitError(e);
    }
  }

  void closePreview() => emit(state.copyWith(previewSeq: null, preview: null));

  Future<void> restore(int fromSeq) async {
    if (state.restoring) return;
    emit(state.copyWith(restoring: true));
    try {
      await _case.restore(
        beaconId: beaconId,
        fromSeq: fromSeq,
        baseRevisionSeq: state.headSeq,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          restoring: false,
          previewSeq: null,
          preview: null,
          restoredFromSeq: fromSeq,
          restoredSeq: state.restoredSeq + 1,
          error: null,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(restoring: false));
      _emitError(e);
    }
    // Either way the head may have moved: reload so the next base is fresh.
    if (!isClosed) await load();
  }

  void _emitError(Object e) => emit(
    state.copyWith(
      error: e,
      errorSeq: state.errorSeq + 1,
      restoredFromSeq: null,
    ),
  );
}
