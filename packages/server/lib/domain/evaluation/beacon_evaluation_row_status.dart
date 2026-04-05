/// Per-row lifecycle in `beacon_evaluation.status` (smallint).
abstract final class BeaconEvaluationRowStatus {
  static const int draft = 0;
  static const int submitted = 1;
  static const int final_ = 2;
  static const int responded = 3;

  /// Rows that count toward summaries and distinct-evaluator counts.
  static bool countsTowardSummary(int status) =>
      status == submitted || status == final_;

  /// Rows visible as "saved" evaluation content (draft or submitted, not deleted).
  static bool isEditableDuringWindow(int status) =>
      status == draft || status == submitted;
}
