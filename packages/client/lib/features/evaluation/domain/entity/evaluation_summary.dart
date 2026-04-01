import 'package:freezed_annotation/freezed_annotation.dart';

part 'evaluation_summary.freezed.dart';

@freezed
abstract class EvaluationSummary with _$EvaluationSummary {
  const factory EvaluationSummary({
    required bool suppressed,
    required String tone,
    required String message,
    @Default([]) List<String> topReasonTags,
    int? neg2,
    int? neg1,
    int? zero,
    int? pos1,
    int? pos2,
  }) = _EvaluationSummary;

  const EvaluationSummary._();
}
