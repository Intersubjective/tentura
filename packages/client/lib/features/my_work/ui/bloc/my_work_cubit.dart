import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';

import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

class MyWorkCubit extends Cubit<MyWorkState> {
  MyWorkCubit({
    required this._userId,
    MyWorkCase? myWorkCase,
  })  : _myWorkCase = myWorkCase ?? GetIt.I<MyWorkCase>(),
       super(const MyWorkState()) {
    _beaconChanges = _myWorkCase.beaconChanges.listen(
      _onBeaconChanged,
      cancelOnError: false,
    );
    _helpOfferChanges = _myWorkCase.helpOfferChanges.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _forwardCompleted = _myWorkCase.forwardCompleted.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _readWatermarkSub = _myWorkCase.readWatermarkChanges.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  final String _userId;
  final MyWorkCase _myWorkCase;

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  late final StreamSubscription<dynamic> _helpOfferChanges;

  late final StreamSubscription<String> _forwardCompleted;

  late final StreamSubscription<String> _readWatermarkSub;

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    await _helpOfferChanges.cancel();
    await _forwardCompleted.cancel();
    await _readWatermarkSub.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    final seq = ++_fetchSeq;
    final filterBefore = state.filter;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        archivedFetchInProgress: false,
      ),
    );
    try {
      final init = await _myWorkCase.loadDeskInit(userId: _userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: init.nonArchivedCards,
          archivedCountHint: init.archivedCountHint,
          finishedArchiveHintDismissed: init.finishedArchiveHintDismissed,
          archivedCards: const [],
          archivedDataFetched: false,
        ),
      );
      if (filterBefore == MyWorkFilter.archived) {
        emit(state.copyWith(archivedFetchInProgress: true));
        unawaited(_loadArchived(seq));
      }
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> archiveBeacon(String beaconId) async {
    await _myWorkCase.archiveBeacon(beaconId: beaconId, userId: _userId);
    _removeBeaconFromState(beaconId);
    emit(
      state.copyWith(
        archivedCountHint: state.archivedCountHint + 1,
        archivedDataFetched: false,
        finishedArchiveHintDismissed: true,
      ),
    );
  }

  Future<void> unarchiveBeacon(String beaconId) async {
    await _myWorkCase.unarchiveBeacon(beaconId: beaconId, userId: _userId);
    emit(
      state.copyWith(
        archivedCards: state.archivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        archivedCountHint: state.archivedCountHint > 0
            ? state.archivedCountHint - 1
            : 0,
      ),
    );
    unawaited(fetch());
  }

  Future<void> dismissFinishedArchiveHint() async {
    if (state.finishedArchiveHintDismissed) return;
    emit(state.copyWith(finishedArchiveHintDismissed: true));
    await _myWorkCase.dismissFinishedArchiveHint(userId: _userId);
  }

  void setFilter(MyWorkFilter filter) {
    if (filter == MyWorkFilter.archived &&
        !state.archivedDataFetched &&
        !state.archivedFetchInProgress) {
      emit(state.copyWith(filter: filter, archivedFetchInProgress: true));
      unawaited(_loadArchived(_fetchSeq));
      return;
    }
    emit(state.copyWith(filter: filter));
  }

  void setSort(MyWorkSort sort) {
    if (state.sort == sort) return;
    emit(state.copyWith(sort: sort));
  }

  Future<void> _loadArchived(int seq) async {
    try {
      final archived = await _myWorkCase.loadDeskArchived(userId: _userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          archivedFetchInProgress: false,
          archivedDataFetched: true,
          archivedCards: archived.archivedCards,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          archivedFetchInProgress: false,
          status: StateHasError(e),
        ),
      );
    }
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventCreate<Beacon>() ||
    RepositoryEventUpdate<Beacon>() ||
    RepositoryEventInvalidate<Beacon>() => unawaited(fetch()),
    RepositoryEventDelete<Beacon>(value: final b) => _removeBeaconFromState(
      b.id,
    ),
    _ => null,
  };

  void _removeBeaconFromState(String beaconId) {
    emit(
      state.copyWith(
        nonArchivedCards: state.nonArchivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        archivedCards: state.archivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
      ),
    );
  }
}
