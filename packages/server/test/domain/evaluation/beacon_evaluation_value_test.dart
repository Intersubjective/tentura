import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';

void main() {
  group('BeaconEvaluationValue', () {
    test('allowsReasonTag excludes NO_BASIS', () {
      expect(BeaconEvaluationValue.allowsReasonTag(BeaconEvaluationValue.noBasis), isFalse);
      expect(BeaconEvaluationValue.allowsReasonTag(BeaconEvaluationValue.zero), isTrue);
    });

    test('isNegative and isPositive classify wire values', () {
      expect(BeaconEvaluationValue.isNegative(BeaconEvaluationValue.neg2), isTrue);
      expect(BeaconEvaluationValue.isNegative(BeaconEvaluationValue.neg1), isTrue);
      expect(BeaconEvaluationValue.isNegative(BeaconEvaluationValue.zero), isFalse);
      expect(BeaconEvaluationValue.isPositive(BeaconEvaluationValue.pos1), isTrue);
      expect(BeaconEvaluationValue.isPositive(BeaconEvaluationValue.pos2), isTrue);
      expect(BeaconEvaluationValue.isPositive(BeaconEvaluationValue.neg1), isFalse);
    });
  });
}
