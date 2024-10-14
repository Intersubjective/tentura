import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/rating_repository.dart';
import 'rating_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'rating_state.dart';

class RatingCubit extends Cubit<RatingState> {
  RatingCubit({
    String initialContext = '',
    RatingRepository? repository,
  })  : _repository = repository ?? GetIt.I<RatingRepository>(),
        super(const RatingState()) {
    fetch(initialContext);
  }

  final RatingRepository _repository;

  Future<void> fetch([String contextName = '']) async {
    emit(state.setLoading());
    try {
      emit(state.copyWith(
        error: null,
        context: contextName,
        status: FetchStatus.isSuccess,
        items: (await _repository.fetch(context: contextName))
            .toList(growable: false),
      ));
      _sort();
    } catch (e) {
      emit(state.setError(e));
    }
  }

  void toggleSortingByAsc() {
    emit(state.copyWith(
      isSortedByAsc: !state.isSortedByAsc,
    ));
    _sort();
  }

  void toggleSortingByEgo() {
    emit(state.copyWith(
      isSortedByEgo: !state.isSortedByEgo,
    ));
    _sort();
  }

  void setSearchFilter(String filter) => emit(state.copyWith(
        searchFilter: filter,
      ));

  void clearSearchFilter() => emit(state.copyWith(
        searchFilter: '',
      ));

  void _sort() {
    if (state.isSortedByEgo) {
      state.items.sort((a, b) {
        final c = state.isSortedByAsc
            ? a.egoScore - b.egoScore
            : b.egoScore - a.egoScore;
        return (c * 10000).toInt();
      });
    } else {
      state.items.sort((a, b) {
        final c = state.isSortedByAsc
            ? a.userScore - b.userScore
            : b.userScore - a.userScore;
        return (c * 10000).toInt();
      });
    }
  }
}
