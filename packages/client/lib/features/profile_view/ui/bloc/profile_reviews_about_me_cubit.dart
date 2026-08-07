import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluations_written_about_viewer.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_reviews_about_me_cubit.freezed.dart';

@freezed
abstract class ProfileReviewsAboutMeState extends StateBase
    with _$ProfileReviewsAboutMeState {
  const factory ProfileReviewsAboutMeState({
    @Default(StateIsSuccess()) StateStatus status,
    @Default([]) List<EvaluationsWrittenAboutViewerRow> rows,
    Object? loadError,
  }) = _ProfileReviewsAboutMeState;

  const ProfileReviewsAboutMeState._();

  bool get hasError => loadError != null;
}

class ProfileReviewsAboutMeCubit extends Cubit<ProfileReviewsAboutMeState> {
  ProfileReviewsAboutMeCubit({
    required this.profileOwnerId,
    EvaluationRepository? evaluationRepository,
  }) : _repository = evaluationRepository ?? GetIt.I<EvaluationRepository>(),
       super(const ProfileReviewsAboutMeState()) {
    unawaited(fetch());
  }

  final String profileOwnerId;
  final EvaluationRepository _repository;
  int _fetchSequence = 0;
  bool _hasLoaded = false;

  Future<void> fetch({
    bool showLoading = true,
  }) async {
    final sequence = ++_fetchSequence;
    if (showLoading) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final rows = await _repository.evaluationsWrittenAboutMeBy(profileOwnerId);
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          rows: rows,
          loadError: null,
        ),
      );
      _hasLoaded = true;
    } catch (e) {
      if (isClosed || sequence != _fetchSequence) return;
      emit(
        state.copyWith(
          loadError: _hasLoaded ? null : e,
          status: const StateIsSuccess(),
        ),
      );
    }
  }
}
