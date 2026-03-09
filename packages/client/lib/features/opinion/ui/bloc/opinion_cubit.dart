import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/opinion.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../data/repository/opinion_repository.dart';
import 'opinion_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'opinion_state.dart';

class OpinionCubit extends Cubit<OpinionState> {
  OpinionCubit({
    required Profile myProfile,
    String profileId = '',
    List<Opinion>? opinions,
    OpinionRepository? opinionRepository,
  }) : _opinionRepository = opinionRepository ?? GetIt.I<OpinionRepository>(),
       super(
         OpinionState(
           myProfile: myProfile,
           objectId: profileId,
           opinions: opinions ?? [],
         ),
       ) {
    unawaited(fetch());
  }

  OpinionCubit.resolveId({
    required String objectId,
    required Profile myProfile,
    OpinionRepository? opinionRepository,
  }) : _opinionRepository = opinionRepository ?? GetIt.I<OpinionRepository>(),
       super(
         OpinionState(
           myProfile: myProfile,
           objectId: objectId,
           opinions: [],
         ),
       ) {
    if (objectId.startsWith('U')) {
      unawaited(fetch());
    } else if (objectId.startsWith('O')) {
      unawaited(
        GetIt.I<OpinionRepository>()
            .fetchById(objectId)
            .then(
              (opinion) => emit(
                state.copyWith(
                  opinions: [opinion],
                  objectId: opinion.objectId,
                ),
              ),
            ),
      );
    } else {
      emit(
        state.copyWith(
          status: StateHasError('Wrong id prefix [$objectId]'),
        ),
      );
    }
  }

  final OpinionRepository _opinionRepository;

  ///
  ///
  Future<void> fetch({bool preserve = true}) async {
    if (state.isLoading ||
        state.myProfile.isEmpty ||
        (state.hasReachedMax && preserve)) {
      return;
    }

    if (preserve) {
      emit(state.copyWith(status: StateStatus.isLoading));
    } else {
      emit(
        state.copyWith(
          opinions: [],
          hasReachedMax: false,
          status: StateStatus.isLoading,
        ),
      );
    }

    try {
      final opinions = await _opinionRepository.fetchByUserId(
        offset: state.opinions.length,
        userId: state.objectId,
      );
      state.opinions
        ..addAll(opinions)
        ..sort((a, b) => a.score.compareTo(b.score));
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          hasReachedMax: opinions.length < kFetchListOffset,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  Future<void> addOpinion({
    required String text,
    required int? amount,
  }) async {
    if (amount == null) return;

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final opinion = await _opinionRepository.createOpinion(
        userId: state.objectId,
        amount: amount,
        content: text,
      );
      state.opinions.add(opinion.copyWith(author: state.myProfile));
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  Future<void> removeOpinionById(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _opinionRepository.removeOpinionById(id);
      state.opinions.removeWhere((e) => e.id == id);
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
