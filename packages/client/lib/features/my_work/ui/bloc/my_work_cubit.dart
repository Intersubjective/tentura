import 'dart:async';

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
  }) : _repository = repository ?? GetIt.I<MyWorkRepository>(),
       _profileCubit = profileCubit ?? GetIt.I<ProfileCubit>(),
       super(const MyWorkState()) {
    unawaited(fetch(initialContext));
  }

  final MyWorkRepository _repository;
  final ProfileCubit _profileCubit;

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
}
