import 'dart:async';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

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

  void setContext(String name) => emit(state.copyWith(context: name));

  Future<void> fetch([String? contextName]) async {
    final ctx = contextName ?? state.context;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
      ),
    );
    try {
      final myId = GetIt.I<AuthCubit>().state.currentAccountId;
      final items = (await _repository.fetch(context: ctx))
          .where((p) => myId.isEmpty || p.id != myId)
          .toList();
      emit(
        state.copyWith(
          context: ctx,
          status: StateStatus.isSuccess,
          items: items,
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

  void toggleSortingByReverse() {
    emit(
      state.copyWith(
        isSortedByReverse: !state.isSortedByReverse,
      ),
    );
    _sort();
  }

  /// Sort by "I trust them" (direct score). If already sorted by this column, toggles asc/desc.
  void sortByDirectColumn() {
    if (!state.isSortedByReverse &&
        !state.isSortedByAlter &&
        !state.isSortedByClass) {
      toggleSortingByAsc();
    } else {
      emit(state.copyWith(
        isSortedByReverse: false,
        isSortedByAlter: false,
        isSortedByClass: false,
        isSortedByAsc: false,
      ));
      _sort();
    }
  }

  /// Sort by "They trust me" (reverse score). If already sorted by this column, toggles asc/desc.
  void sortByReverseColumn() {
    if (state.isSortedByReverse &&
        !state.isSortedByAlter &&
        !state.isSortedByClass) {
      toggleSortingByAsc();
    } else {
      emit(state.copyWith(
        isSortedByReverse: true,
        isSortedByAlter: false,
        isSortedByClass: false,
        isSortedByAsc: false,
      ));
      _sort();
    }
  }

  /// Sort by Alter (name/title). If already sorted by this column, toggles asc/desc.
  void sortByAlterColumn() {
    if (state.isSortedByAlter) {
      toggleSortingByAsc();
    } else {
      emit(state.copyWith(
        isSortedByAlter: true,
        isSortedByReverse: false,
        isSortedByClass: false,
        isSortedByAsc: true,
      ));
      _sort();
    }
  }

  /// Sort by Class (reciprocity). If already sorted by this column, toggles asc/desc.
  void sortByClassColumn() {
    if (state.isSortedByClass) {
      toggleSortingByAsc();
    } else {
      emit(state.copyWith(
        isSortedByClass: true,
        isSortedByReverse: false,
        isSortedByAlter: false,
        isSortedByAsc: true,
      ));
      _sort();
    }
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

  static const _kSupportThreshold = 10.0;

  static int _reciprocityOrder(Profile p) {
    final dp = p.score > _kSupportThreshold;
    final rp = p.rScore > _kSupportThreshold;
    if (dp && rp) return 0; // mutual
    if (dp && !rp) return 1; // oneWayOut
    if (!dp && rp) return 2; // oneWayIn
    return 3; // none
  }

  void _sort() {
    final asc = state.isSortedByAsc;
    if (state.isSortedByAlter) {
      state.items.sort((a, b) {
        final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return asc ? c : -c;
      });
    } else if (state.isSortedByClass) {
      state.items.sort((a, b) {
        final oa = _reciprocityOrder(a);
        final ob = _reciprocityOrder(b);
        final c = oa.compareTo(ob);
        return asc ? c : -c;
      });
    } else if (state.isSortedByReverse) {
      state.items.sort(
        (a, b) =>
            10000 *
            (asc ? a.rScore - b.rScore : b.rScore - a.rScore)
                .toInt(),
      );
    } else {
      state.items.sort(
        (a, b) =>
            10000 *
            (asc ? a.score - b.score : b.score - a.score)
                .toInt(),
      );
    }
  }
}
