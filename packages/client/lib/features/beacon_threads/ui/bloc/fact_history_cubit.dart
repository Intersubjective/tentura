import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'fact_history_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

/// Issue #181 plan §14.2/§14.6: a thin single-repository cubit loading a
/// fact card's history timeline. Never calls RoomCubit.
class FactHistoryCubit extends Cubit<FactHistoryState> {
  FactHistoryCubit({
    required String beaconId,
    required String factCardId,
    required int baseRevisionSeq,
    BeaconFactCardRepository? repository,
  }) : _beaconId = beaconId,
       _factCardId = factCardId,
       _baseRevisionSeq = baseRevisionSeq,
       _repository = repository ?? GetIt.I<BeaconFactCardRepository>(),
       super(const FactHistoryState());

  final String _beaconId;
  final String _factCardId;

  /// Fixed at construction time (the revision the sheet opened with),
  /// never refetched.
  final int _baseRevisionSeq;

  final BeaconFactCardRepository _repository;

  Future<void> load() => _loadPage(before: null, append: false);

  Future<void> loadMore() {
    final cursor = state.nextCursor;
    if (cursor == null) return Future<void>.value();
    return _loadPage(before: cursor, append: true);
  }

  Future<void> restore(int fromSeq) async {
    try {
      await _repository.restore(
        beaconId: _beaconId,
        factCardId: _factCardId,
        fromSeq: fromSeq,
        baseRevisionSeq: _baseRevisionSeq,
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      return;
    }
    if (isClosed) return;
    await _loadPage(before: null, append: false);
  }

  Future<void> _loadPage({required String? before, required bool append}) async {
    if (!append) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final page = await _repository.revisions(
        beaconId: _beaconId,
        factCardId: _factCardId,
        before: before,
      );
      if (isClosed) return;
      final entries = EqualUnmodifiableListView<BeaconFactTimelineEntry>(
        append ? [...state.entries, ...page.entries] : page.entries,
      );
      emit(
        state.copyWith(
          entries: entries,
          nextCursor: page.nextCursor,
          loadError: null,
          status: const StateIsSuccess(),
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
    }
  }
}
