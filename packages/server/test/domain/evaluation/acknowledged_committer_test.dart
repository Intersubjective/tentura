import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/evaluation/acknowledged_committer.dart';

void main() {
  group('isAcknowledgedCommitterResponse', () {
    test('accepts useful and needCoordination', () {
      expect(
        isAcknowledgedCommitterResponse(
          CoordinationResponseType.useful.smallintValue,
        ),
        isTrue,
      );
      expect(
        isAcknowledgedCommitterResponse(
          CoordinationResponseType.needCoordination.smallintValue,
        ),
        isTrue,
      );
    });

    test('rejects unacknowledged and rejected responses', () {
      for (final t in [
        null,
        CoordinationResponseType.overlapping.smallintValue,
        CoordinationResponseType.needDifferentSkill.smallintValue,
        CoordinationResponseType.notSuitable.smallintValue,
      ]) {
        expect(isAcknowledgedCommitterResponse(t), isFalse);
      }
    });
  });
}
