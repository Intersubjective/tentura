/// Wire / DB encoding for `beacon_evaluation.value`.
abstract final class BeaconEvaluationValue {
  static const int noBasis = 0;
  static const int neg2 = 1;
  static const int neg1 = 2;
  static const int zero = 3;
  static const int pos1 = 4;
  static const int pos2 = 5;

  static bool requiresReasonTag(int v) =>
      v == neg2 || v == neg1 || v == pos2;

  static bool allowsReasonTag(int v) => v != noBasis;

  static bool isNegative(int v) => v == neg2 || v == neg1;

  static bool isPositive(int v) => v == pos1 || v == pos2;
}
