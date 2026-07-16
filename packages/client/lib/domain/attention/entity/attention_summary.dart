import 'package:freezed_annotation/freezed_annotation.dart';

part 'attention_summary.freezed.dart';

@freezed
abstract class AttentionSummary with _$AttentionSummary {
  const factory AttentionSummary({@Default(0) int unreadTotal}) =
      _AttentionSummary;
}
