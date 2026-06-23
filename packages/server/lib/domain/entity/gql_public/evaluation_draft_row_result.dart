import 'package:meta/meta.dart';

/// One saved draft row (GraphQL `EvaluationDraftRow`).
@immutable
class EvaluationDraftRowResult {
  const EvaluationDraftRowResult({
    required this.evaluatedUserId,
    required this.value,
    required this.reasonTags,
    required this.note,
  });

  final String evaluatedUserId;
  final int value;
  final List<String> reasonTags;
  final String note;
}
