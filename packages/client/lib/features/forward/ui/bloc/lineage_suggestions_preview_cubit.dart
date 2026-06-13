import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/forward_case.dart';
import 'lineage_suggestions_preview_state.dart';

@injectable
class LineageSuggestionsPreviewCubit extends Cubit<LineageSuggestionsPreviewState> {
  LineageSuggestionsPreviewCubit(this._forwardCase)
      : super(const LineageSuggestionsPreviewState());

  final ForwardCase _forwardCase;

  Future<void> load(String beaconId) async {
    emit(state.copyWith(beaconId: beaconId, status: StateStatus.isLoading));
    try {
      final rows = await _forwardCase.loadLineageSuggestionsPreview(
        beaconId: beaconId,
      );
      emit(
        state.copyWith(
          rows: rows,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
