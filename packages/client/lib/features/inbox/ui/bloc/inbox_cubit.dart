import 'dart:async';
import 'package:get_it/get_it.dart';

import '../../data/repository/inbox_repository.dart';
import 'inbox_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'inbox_state.dart';

class InboxCubit extends Cubit<InboxState> {
  InboxCubit({
    String initialContext = '',
    InboxRepository? repository,
  }) : _repository = repository ?? GetIt.I<InboxRepository>(),
       super(const InboxState()) {
    unawaited(fetch(initialContext));
  }

  final InboxRepository _repository;

  Future<void> fetch([String? contextName]) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final items = await _repository.fetch(
        context: contextName ?? state.context,
      );
      emit(
        InboxState(
          context: contextName ?? state.context,
          items: items,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> hide(String beaconId) async {
    try {
      await _repository.setHidden(beaconId: beaconId, isHidden: true);
      emit(
        state.copyWith(
          items: state.items.where((e) => e.beaconId != beaconId).toList(),
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> toggleWatching(String beaconId) async {
    final idx = state.items.indexWhere((e) => e.beaconId == beaconId);
    if (idx < 0) return;
    final item = state.items[idx];
    final newWatching = !item.isWatching;
    try {
      await _repository.setWatching(
        beaconId: beaconId,
        isWatching: newWatching,
      );
      emit(
        state.copyWith(
          items: [
            ...state.items.sublist(0, idx),
            item.copyWith(isWatching: newWatching),
            ...state.items.sublist(idx + 1),
          ],
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
