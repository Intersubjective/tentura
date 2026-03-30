import 'dart:async';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../data/repository/my_work_repository.dart';
import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

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
          authoredActive: const [],
          authoredClosed: const [],
          committedActive: const [],
          committedClosed: const [],
        ),
      );
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final results = await Future.wait([
        _repository.fetchAuthoredActive(userId: userId, context: ctx),
        _repository.fetchAuthoredClosed(userId: userId, context: ctx),
        _repository.fetchCommittedActive(userId: userId, context: ctx),
        _repository.fetchCommittedClosed(userId: userId, context: ctx),
      ]);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          context: ctx,
          authoredActive: results[0],
          authoredClosed: results[1],
          committedActive: results[2],
          committedClosed: results[3],
        ),
      );
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
    emit(state.copyWith(section: section));
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventUpdate<Beacon>() => unawaited(fetch()),
    RepositoryEventDelete<Beacon>(value: final b) => emit(
      state.copyWith(
        authoredActive:
            state.authoredActive.where((e) => e.id != b.id).toList(),
        authoredClosed:
            state.authoredClosed.where((e) => e.id != b.id).toList(),
        committedActive:
            state.committedActive.where((e) => e.id != b.id).toList(),
        committedClosed:
            state.committedClosed.where((e) => e.id != b.id).toList(),
      ),
    ),
    _ => null,
  };
}
