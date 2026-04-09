import 'dart:async';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../data/repository/my_work_repository.dart';
import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

class MyWorkCubit extends Cubit<MyWorkState> {
  MyWorkCubit({
    MyWorkRepository? repository,
    ProfileCubit? profileCubit,
    BeaconRepository? beaconRepository,
    ForwardRepository? forwardRepository,
  }) : _repository = repository ?? GetIt.I<MyWorkRepository>(),
       _profileCubit = profileCubit ?? GetIt.I<ProfileCubit>(),
       super(const MyWorkState()) {
    _beaconChanges = (beaconRepository ?? GetIt.I<BeaconRepository>())
        .changes
        .listen(_onBeaconChanged, cancelOnError: false);
    _commitmentChanges =
        (forwardRepository ?? GetIt.I<ForwardRepository>())
            .commitmentChanges
            .listen((_) => unawaited(fetch()), cancelOnError: false);
    unawaited(fetch());
  }

  final MyWorkRepository _repository;
  final ProfileCubit _profileCubit;

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  late final StreamSubscription<CommitmentEvent> _commitmentChanges;

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    await _commitmentChanges.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    final seq = ++_fetchSeq;
    final userId = _profileCubit.state.profile.id;
    if (userId.isEmpty) {
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: const [],
          archivedCards: const [],
          authoredClosedIdHints: const [],
          committedClosedIdHints: const [],
          closedDataFetched: false,
          closedFetchInProgress: false,
        ),
      );
      return;
    }
    final filterBefore = state.filter;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        closedFetchInProgress: false,
      ),
    );
    try {
      final init = await _repository.fetchInit(userId: userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      final nonArchived = buildNonArchivedViewModels(
        authoredNonClosed: init.authoredNonClosed,
        committedNonClosed: init.committedNonClosed,
      );
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: nonArchived,
          authoredClosedIdHints: init.authoredClosedIds,
          committedClosedIdHints: init.committedClosedIds,
          closedDataFetched: false,
          archivedCards: const [],
        ),
      );
      if (filterBefore == MyWorkFilter.archived) {
        emit(state.copyWith(closedFetchInProgress: true));
        unawaited(_fetchClosed(seq));
      }
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void setFilter(MyWorkFilter filter) {
    if (filter == MyWorkFilter.archived &&
        !state.closedDataFetched &&
        !state.closedFetchInProgress) {
      emit(state.copyWith(filter: filter, closedFetchInProgress: true));
      unawaited(_fetchClosed(_fetchSeq));
      return;
    }
    emit(state.copyWith(filter: filter));
  }

  Future<void> _fetchClosed(int seq) async {
    final userId = _profileCubit.state.profile.id;
    if (userId.isEmpty) {
      if (!isClosed && seq == _fetchSeq) {
        emit(state.copyWith(closedFetchInProgress: false));
      }
      return;
    }
    try {
      final closed = await _repository.fetchClosed(userId: userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      final archived = buildArchivedViewModels(
        authoredClosed: closed.authoredClosed,
        committedClosed: closed.committedClosed,
      );
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          closedDataFetched: true,
          archivedCards: archived,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          status: StateHasError(e),
        ),
      );
    }
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
        RepositoryEventUpdate<Beacon>() => unawaited(fetch()),
        RepositoryEventDelete<Beacon>(value: final b) => emit(
          state.copyWith(
            nonArchivedCards: state.nonArchivedCards
                .where((c) => c.beaconId != b.id)
                .toList(),
            archivedCards:
                state.archivedCards.where((c) => c.beaconId != b.id).toList(),
            authoredClosedIdHints:
                state.authoredClosedIdHints.where((id) => id != b.id).toList(),
            committedClosedIdHints:
                state.committedClosedIdHints.where((id) => id != b.id).toList(),
          ),
        ),
        _ => null,
      };
}
