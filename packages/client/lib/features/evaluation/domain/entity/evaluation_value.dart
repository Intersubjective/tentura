/// Matches server `beacon_evaluation.value` encoding.
enum EvaluationValue {
  noBasis(0),
  neg2(1),
  neg1(2),
  zero(3),
  pos1(4),
  pos2(5);

  const EvaluationValue(this.wire);

  final int wire;

  static EvaluationValue? fromWire(int? v) {
    if (v == null) {
      return null;
    }
    for (final e in EvaluationValue.values) {
      if (e.wire == v) {
        return e;
      }
    }
    return null;
  }

  bool get requiresReasonTag =>
      this == EvaluationValue.neg2 ||
      this == EvaluationValue.neg1 ||
      this == EvaluationValue.pos2;

  bool get allowsReasonTag => this != EvaluationValue.noBasis;
}
