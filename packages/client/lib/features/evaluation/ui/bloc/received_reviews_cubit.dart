import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

part 'received_reviews_cubit.freezed.dart';

@freezed
abstract class ReceivedReviewsState extends StateBase with _$ReceivedReviewsState {
  const factory ReceivedReviewsState({
    @Default(StateIsSuccess()) StateStatus status,
    EvaluationReceived? data,
    Object? loadError,
  }) = _ReceivedReviewsState;

  const ReceivedReviewsState._();

  bool get hasError => loadError != null;
}

class ReceivedReviewsCubit extends Cubit<ReceivedReviewsState> {
  ReceivedReviewsCubit(
    this._repository, {
    required this.beaconId,
  }) : super(const ReceivedReviewsState()) {
    unawaited(fetch());
  }

  factory ReceivedReviewsCubit.fromGetIt({required String beaconId}) =>
      ReceivedReviewsCubit(GetIt.I<EvaluationRepository>(), beaconId: beaconId);

  final EvaluationRepository _repository;
  final String beaconId;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading, loadError: null));
    try {
      final data = await _repository.evaluationReceived(beaconId);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          data: data,
          loadError: null,
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          loadError: error,
        ),
      );
    }
  }
}
