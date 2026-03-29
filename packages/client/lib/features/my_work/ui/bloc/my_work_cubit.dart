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

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    return super.close();
  }

  Future<void> fetch([String? contextName]) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final ctx = contextName ?? state.context;
      final userId = _profileCubit.state.profile.id;
      final results = await Future.wait([
        _repository.fetchAuthored(userId: userId, context: ctx),
        _repository.fetchCommitted(userId: userId, context: ctx),
      ]);
      emit(
        MyWorkState(
          context: ctx,
          authored: results[0],
          committed: results[1],
          filter: state.filter,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void setFilter(MyWorkFilter filter) {
    emit(state.copyWith(filter: filter));
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventUpdate<Beacon>(value: final b) => emit(state.copyWith(
      authored: [for (final a in state.authored) a.id == b.id ? b : a],
      committed: [for (final c in state.committed) c.id == b.id ? b : c],
    )),
    RepositoryEventDelete<Beacon>(value: final b) => emit(state.copyWith(
      authored: state.authored.where((e) => e.id != b.id).toList(),
      committed: state.committed.where((e) => e.id != b.id).toList(),
    )),
    _ => null,
  };
}
