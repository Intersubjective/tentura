import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_row_status.dart';

void main() {
  group('countsTowardSummary', () {
    test('true for submitted and final rows', () {
      expect(
        BeaconEvaluationRowStatus.countsTowardSummary(
          BeaconEvaluationRowStatus.submitted,
        ),
        isTrue,
      );
      expect(
        BeaconEvaluationRowStatus.countsTowardSummary(
          BeaconEvaluationRowStatus.final_,
        ),
        isTrue,
      );
    });

    test('false for draft and responded rows', () {
      expect(
        BeaconEvaluationRowStatus.countsTowardSummary(
          BeaconEvaluationRowStatus.draft,
        ),
        isFalse,
      );
      expect(
        BeaconEvaluationRowStatus.countsTowardSummary(
          BeaconEvaluationRowStatus.responded,
        ),
        isFalse,
      );
    });
  });

  group('isEditableDuringWindow', () {
    test('true for draft and submitted', () {
      expect(
        BeaconEvaluationRowStatus.isEditableDuringWindow(
          BeaconEvaluationRowStatus.draft,
        ),
        isTrue,
      );
      expect(
        BeaconEvaluationRowStatus.isEditableDuringWindow(
          BeaconEvaluationRowStatus.submitted,
        ),
        isTrue,
      );
    });

    test('false for final and responded', () {
      expect(
        BeaconEvaluationRowStatus.isEditableDuringWindow(
          BeaconEvaluationRowStatus.final_,
        ),
        isFalse,
      );
      expect(
        BeaconEvaluationRowStatus.isEditableDuringWindow(
          BeaconEvaluationRowStatus.responded,
        ),
        isFalse,
      );
    });
  });
}
