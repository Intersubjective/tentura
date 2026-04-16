import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/polling_case.dart';
import 'polling_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'polling_state.dart';

class PollingCubit extends Cubit<PollingState> {
  PollingCubit({
    required Polling polling,
    PollingCase? pollingCase,
  }) : _pollingCase = pollingCase ?? GetIt.I<PollingCase>(),
       super(
         PollingState(
           polling: polling,
           chosenVariant: polling.selection.firstOrNull ?? '',
         ),
       );

  final PollingCase _pollingCase;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final (:polling, :results) = await _pollingCase.fetchResults(
        pollingId: state.polling.id,
      );
      emit(
        state.copyWith(
          polling: polling,
          results: results,
          chosenVariant: polling.selection.firstOrNull ?? '',
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void chooseVariant(String variantId) {
    emit(state.copyWith(chosenVariant: variantId));
  }

  Future<void> vote() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _pollingCase.vote(
        pollingId: state.polling.id,
        variantId: state.chosenVariant,
      );
      await fetch();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
