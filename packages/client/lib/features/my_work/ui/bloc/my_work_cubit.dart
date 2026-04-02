import 'dart:async';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../data/repository/my_work_repository.dart';
import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

/// Splits non-closed My Work fetch results into Drafts / Active / Review tabs.
({List<Beacon> drafts, List<Beacon> active, List<Beacon> review})
partitionMyWorkNonClosed(Iterable<Beacon> beacons) {
  final drafts = <Beacon>[];
  final active = <Beacon>[];
  final review = <Beacon>[];
  for (final b in beacons) {
    if (b.lifecycle.isMyWorkDraftsTab) {
      drafts.add(b);
    } else if (b.lifecycle.isMyWorkActiveTab) {
      active.add(b);
    } else if (b.lifecycle.isMyWorkReviewTab) {
      review.add(b);
    }
  }
  return (drafts: drafts, active: active, review: review);
}

class MyWorkCubit extends Cubit<MyWorkState> {
  MyWorkCubit({
    String initialContext = '',
    MyWorkRepository? repository,
    ProfileCubit? profileCubit,
    BeaconRepository? beaconRepository,
  }) : _repository = repository ?? GetIt.I<MyWorkRepository>(),
       _profileCubit = profileCubit ?? GetIt.I<ProfileCubit>(),
       super(const MyWorkState()) {
    _beaconChanges = (beaconRepository ?? GetIt.I<BeaconRepository>())
        .changes
        .listen(_onBeaconChanged, cancelOnError: false);
    unawaited(fetch(initialContext));
  }

  final MyWorkRepository _repository;
  final ProfileCubit _profileCubit;

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    return super.close();
  }

  Future<void> fetch([String? contextName]) async {
    final seq = ++_fetchSeq;
    final ctx = contextName ?? state.context;
    final userId = _profileCubit.state.profile.id;
    if (userId.isEmpty) {
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          context: ctx,
          authoredDrafts: const [],
          authoredActive: const [],
          authoredReview: const [],
          authoredClosed: const [],
          committedDrafts: const [],
          committedActive: const [],
          committedReview: const [],
          committedClosed: const [],
          authoredClosedIdHints: const [],
          committedClosedIdHints: const [],
          closedDataFetched: false,
          closedFetchInProgress: false,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        closedFetchInProgress: false,
      ),
    );
    try {
      final init = await _repository.fetchInit(userId: userId, context: ctx);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      final authored = partitionMyWorkNonClosed(init.authoredNonClosed);
      final committed = partitionMyWorkNonClosed(init.committedNonClosed);
      final next = state.copyWith(
        status: const StateIsSuccess(),
        context: ctx,
        authoredDrafts: authored.drafts,
        authoredActive: authored.active,
        authoredReview: authored.review,
        authoredClosed: const [],
        committedDrafts: committed.drafts,
        committedActive: committed.active,
        committedReview: committed.review,
        committedClosed: const [],
        authoredClosedIdHints: init.authoredClosedIds,
        committedClosedIdHints: init.committedClosedIds,
        closedDataFetched: false,
      );
      emit(next);
      if (next.section == MyWorkSection.closed && !next.closedDataFetched) {
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
    emit(state.copyWith(filter: filter));
  }

  void setSection(MyWorkSection section) {
    if (section == MyWorkSection.closed &&
        !state.closedDataFetched &&
        !state.closedFetchInProgress) {
      emit(state.copyWith(section: section, closedFetchInProgress: true));
      unawaited(_fetchClosed(_fetchSeq));
      return;
    }
    emit(state.copyWith(section: section));
  }

  Future<void> _fetchClosed(int seq) async {
    final userId = _profileCubit.state.profile.id;
    final ctx = state.context;
    if (userId.isEmpty) {
      if (!isClosed && seq == _fetchSeq) {
        emit(state.copyWith(closedFetchInProgress: false));
      }
      return;
    }
    try {
      final closed = await _repository.fetchClosed(
        userId: userId,
        context: ctx,
      );
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          closedDataFetched: true,
          authoredClosed: closed.authoredClosed,
          committedClosed: closed.committedClosed,
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
            authoredDrafts:
                state.authoredDrafts.where((e) => e.id != b.id).toList(),
            authoredActive:
                state.authoredActive.where((e) => e.id != b.id).toList(),
            authoredReview:
                state.authoredReview.where((e) => e.id != b.id).toList(),
            authoredClosed:
                state.authoredClosed.where((e) => e.id != b.id).toList(),
            committedDrafts:
                state.committedDrafts.where((e) => e.id != b.id).toList(),
            committedActive:
                state.committedActive.where((e) => e.id != b.id).toList(),
            committedReview:
                state.committedReview.where((e) => e.id != b.id).toList(),
            committedClosed:
                state.committedClosed.where((e) => e.id != b.id).toList(),
            authoredClosedIdHints:
                state.authoredClosedIdHints.where((id) => id != b.id).toList(),
            committedClosedIdHints:
                state.committedClosedIdHints.where((id) => id != b.id).toList(),
          ),
        ),
        _ => null,
      };
}
