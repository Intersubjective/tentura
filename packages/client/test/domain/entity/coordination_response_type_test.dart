import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/coordination_response_type.dart';

void main() {
  group('CoordinationResponseType.tryFromInt', () {
    test('maps known response type values', () {
      expect(
        CoordinationResponseType.tryFromInt(0),
        CoordinationResponseType.useful,
      );
      expect(
        CoordinationResponseType.tryFromInt(1),
        CoordinationResponseType.overlapping,
      );
      expect(
        CoordinationResponseType.tryFromInt(2),
        CoordinationResponseType.needDifferentSkill,
      );
      expect(
        CoordinationResponseType.tryFromInt(3),
        CoordinationResponseType.needCoordination,
      );
      expect(
        CoordinationResponseType.tryFromInt(4),
        CoordinationResponseType.notSuitable,
      );
    });

    test('returns null for null input', () {
      expect(CoordinationResponseType.tryFromInt(null), isNull);
    });

    test('returns null for unknown values', () {
      expect(CoordinationResponseType.tryFromInt(99), isNull);
    });
  });
}
