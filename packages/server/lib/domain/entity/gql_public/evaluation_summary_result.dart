import 'package:meta/meta.dart';

/// Aggregated evaluation summary for one participant (GraphQL `EvaluationSummary`).
@immutable
class EvaluationSummaryResult {
  const EvaluationSummaryResult({
    required this.suppressed,
    required this.tone,
    required this.message,
    required this.topReasonTags,
    required this.roleSummaryLine,
    this.neg2,
    this.neg1,
    this.zero,
    this.pos1,
    this.pos2,
  });

  final bool suppressed;
  final String tone;
  final String message;
  final List<String> topReasonTags;
  final int? neg2;
  final int? neg1;
  final int? zero;
  final int? pos1;
  final int? pos2;
  final String roleSummaryLine;
}
