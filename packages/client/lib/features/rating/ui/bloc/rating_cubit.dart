import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';

import '../../data/repository/rating_repository.dart';
import 'rating_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'rating_state.dart';

class RatingCubit extends Cubit<RatingState> {
  RatingCubit({
    String initialContext = '',
    RatingRepository? repository,
  }) : _repository = repository ?? GetIt.I<RatingRepository>(),
       super(const RatingState()) {
    unawaited(fetch(initialContext));
  }

  final RatingRepository _repository;

  void showProfile(String id) => emit(
    state.copyWith(
      status: StateIsNavigating('$kPathProfileView/$id'),
    ),
  );

  Future<void> fetch([String contextName = '']) async {
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
      ),
    );
    try {
      emit(
        state.copyWith(
          context: contextName,
          status: StateStatus.isSuccess,
          items: (await _repository.fetch(context: contextName)).toList(),
        ),
      );
      _sort();
    } catch (e) {
      emit(
        state.copyWith(
          status: StateHasError(e),
        ),
      );
    }
  }

  void toggleSortingByAsc() {
    emit(
      state.copyWith(
        isSortedByAsc: !state.isSortedByAsc,
      ),
    );
    _sort();
  }

  void toggleSortingByEgo() {
    emit(
      state.copyWith(
        isSortedByEgo: !state.isSortedByEgo,
      ),
    );
    _sort();
  }

  void setSearchFilter(String filter) => emit(
    state.copyWith(
      searchFilter: filter,
    ),
  );

  void clearSearchFilter() => emit(
    state.copyWith(
      searchFilter: '',
    ),
  );

  void _sort() {
    if (state.isSortedByEgo) {
      state.items.sort(
        (a, b) =>
            10000 *
            (state.isSortedByAsc ? a.rScore - b.rScore : b.rScore - a.rScore)
                .toInt(),
      );
    } else {
      state.items.sort(
        (a, b) =>
            10000 *
            (state.isSortedByAsc ? a.score - b.score : b.score - a.score)
                .toInt(),
      );
    }
  }
}
