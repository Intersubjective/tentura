import 'dart:async';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
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
    NewStuffCubit? newStuffCubit,
  }) : _repository = repository ?? GetIt.I<MyWorkRepository>(),
       _profileCubit = profileCubit ?? GetIt.I<ProfileCubit>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       _newStuffCubit = newStuffCubit ?? GetIt.I<NewStuffCubit>(),
       super(const MyWorkState()) {
    _beaconChanges = (beaconRepository ?? GetIt.I<BeaconRepository>())
        .changes
        .listen(_onBeaconChanged, cancelOnError: false);
    _commitmentChanges = _forwardRepository.commitmentChanges.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _forwardCompleted = _forwardRepository.forwardCompleted.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  final MyWorkRepository _repository;
  final ProfileCubit _profileCubit;
  final ForwardRepository _forwardRepository;
  final NewStuffCubit _newStuffCubit;

  void _reportMyWorkActivity() {
    if (!state.isSuccess) return;
    int? maxMs;
    for (final c in state.nonArchivedCards) {
      final m = c.newStuffActivityEpochMs;
      if (maxMs == null || m > maxMs) maxMs = m;
    }
    for (final c in state.archivedCards) {
      final m = c.newStuffActivityEpochMs;
      if (maxMs == null || m > maxMs) maxMs = m;
    }
    _newStuffCubit.reportMyWorkActivity(maxMs);
  }

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  late final StreamSubscription<CommitmentEvent> _commitmentChanges;

  late final StreamSubscription<String> _forwardCompleted;

  Future<List<MyWorkCardViewModel>> _withAuthorForwardFlags(
    List<MyWorkCardViewModel> cards,
  ) async {
    final needsFlag = cards
        .where((c) => c.kind != MyWorkCardKind.authoredDraft)
        .toList();
    if (needsFlag.isEmpty) {
      return cards;
    }
    final results = await Future.wait(
      needsFlag.map(
        (c) => _forwardRepository.currentUserHasForwardedBeacon(c.beaconId),
      ),
    );
    final map = <String, bool>{
      for (var i = 0; i < needsFlag.length; i++)
        needsFlag[i].beaconId: results[i],
    };
    return [
      for (final c in cards)
        c.kind == MyWorkCardKind.authoredDraft
            ? c
            : c.copyWith(authorHasForwardedOnce: map[c.beaconId] ?? false),
    ];
  }

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    await _commitmentChanges.cancel();
    await _forwardCompleted.cancel();
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
      _reportMyWorkActivity();
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
      final withForwardFlags = await _withAuthorForwardFlags(nonArchived);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          nonArchivedCards: withForwardFlags,
          authoredClosedIdHints: init.authoredClosedIds,
          committedClosedIdHints: init.committedClosedIds,
          closedDataFetched: false,
          archivedCards: const [],
        ),
      );
      _reportMyWorkActivity();
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
      final archivedWithForwardFlags = await _withAuthorForwardFlags(archived);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          closedFetchInProgress: false,
          closedDataFetched: true,
          archivedCards: archivedWithForwardFlags,
          status: const StateIsSuccess(),
        ),
      );
      _reportMyWorkActivity();
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
        RepositoryEventCreate<Beacon>() ||
        RepositoryEventUpdate<Beacon>() ||
        RepositoryEventInvalidate<Beacon>() =>
          unawaited(fetch()),
        RepositoryEventDelete<Beacon>(value: final b) =>
          _removeBeaconFromState(b.id),
        _ => null,
      };

  void _removeBeaconFromState(String beaconId) {
    emit(
      state.copyWith(
        nonArchivedCards:
            state.nonArchivedCards.where((c) => c.beaconId != beaconId).toList(),
        archivedCards:
            state.archivedCards.where((c) => c.beaconId != beaconId).toList(),
        authoredClosedIdHints:
            state.authoredClosedIdHints.where((id) => id != beaconId).toList(),
        committedClosedIdHints:
            state.committedClosedIdHints.where((id) => id != beaconId).toList(),
      ),
    );
    _reportMyWorkActivity();
  }
}
