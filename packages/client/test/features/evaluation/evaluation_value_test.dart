import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';

void main() {
  test('fromWire roundtrip', () {
    expect(EvaluationValue.fromWire(0), EvaluationValue.noBasis);
    expect(EvaluationValue.fromWire(5), EvaluationValue.pos2);
    expect(EvaluationValue.fromWire(null), isNull);
  });

  test('requiresReasonTag', () {
    expect(EvaluationValue.neg2.requiresReasonTag, isTrue);
    expect(EvaluationValue.neg1.requiresReasonTag, isTrue);
    expect(EvaluationValue.pos2.requiresReasonTag, isTrue);
    expect(EvaluationValue.pos1.requiresReasonTag, isFalse);
    expect(EvaluationValue.zero.requiresReasonTag, isFalse);
    expect(EvaluationValue.noBasis.allowsReasonTag, isFalse);
    expect(EvaluationValue.zero.allowsReasonTag, isTrue);
  });

  test('fromWire returns null for unknown wire values', () {
    expect(EvaluationValue.fromWire(99), isNull);
  });
}
