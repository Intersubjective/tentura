import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';

void main() {
  group('BeaconEvaluationValue', () {
    test('requiresReasonTag for extremes', () {
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.neg2), isTrue);
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.neg1), isTrue);
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.pos2), isTrue);
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.pos1), isFalse);
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.zero), isFalse);
      expect(BeaconEvaluationValue.requiresReasonTag(BeaconEvaluationValue.noBasis), isFalse);
    });

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
