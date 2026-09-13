import 'package:freezed_annotation/freezed_annotation.dart';

part 'attention_summary.freezed.dart';

@freezed
abstract class AttentionSummary with _$AttentionSummary {
  const factory AttentionSummary({
    @Default(0) int unreadTotal,
    @Default(0) int needsYouTotal,
  }) = _AttentionSummary;
}

@freezed
abstract class AttentionSurfaceSummary with _$AttentionSurfaceSummary {
  const factory AttentionSurfaceSummary({
    required int activityUnreadTotal,
    required int myWorkUnreadTotal,
    required int needsYouTotal,
  }) = _AttentionSurfaceSummary;
}
