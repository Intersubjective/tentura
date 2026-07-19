import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_close_snapshot.freezed.dart';

@freezed
abstract class FinalizedEvaluation with _$FinalizedEvaluation {
  const factory FinalizedEvaluation({
    required String evaluatorId,
    required String evaluatedUserId,
    required int value,
  }) = _FinalizedEvaluation;
}

@freezed
abstract class ReviewCloseSnapshot with _$ReviewCloseSnapshot {
  const factory ReviewCloseSnapshot({
    required String beaconId,
    required String beaconAuthorId,
    required DateTime windowOpenedAt,
    required List<FinalizedEvaluation> finalizedEvaluations,
  }) = _ReviewCloseSnapshot;
}
