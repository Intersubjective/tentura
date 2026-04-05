import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';
import 'package:tentura_server/domain/evaluation/evaluation_summary_rules.dart';

void main() {
  group('evaluationToneFromValues', () {
    test('positive when sum > 0', () {
      expect(
        evaluationToneFromValues([
          BeaconEvaluationValue.pos1,
          BeaconEvaluationValue.pos1,
        ]),
        'positive',
      );
    });

    test('negative when sum < 0', () {
      expect(
        evaluationToneFromValues([
          BeaconEvaluationValue.neg2,
          BeaconEvaluationValue.pos1,
        ]),
        'negative',
      );
    });

    test('mixed when sum == 0', () {
      expect(
        evaluationToneFromValues([
          BeaconEvaluationValue.neg1,
          BeaconEvaluationValue.pos1,
        ]),
        'mixed',
      );
      expect(evaluationToneFromValues([BeaconEvaluationValue.zero]), 'mixed');
    });

    test('ignores noBasis and unknown values', () {
      expect(
        evaluationToneFromValues([
          BeaconEvaluationValue.noBasis,
          BeaconEvaluationValue.pos2,
          BeaconEvaluationValue.pos2,
        ]),
        'positive',
      );
    });
  });

  group('evaluationSummaryAggregates', () {
    test('counts value buckets and top tags by frequency', () {
      final agg = evaluationSummaryAggregates([
        (value: BeaconEvaluationValue.neg1, reasonTagsCsv: 'a,b'),
        (value: BeaconEvaluationValue.neg1, reasonTagsCsv: 'a'),
        (value: BeaconEvaluationValue.pos2, reasonTagsCsv: 'c'),
      ]);
      expect(agg.neg1, 2);
      expect(agg.pos2, 1);
      expect(agg.neg2, 0);
      expect(agg.zero, 0);
      expect(agg.pos1, 0);
      expect(agg.topReasonTags.first, 'a');
      expect(agg.topReasonTags.length, lessThanOrEqualTo(5));
    });

    test('top tags ordered by frequency; ties unspecified', () {
      final agg = evaluationSummaryAggregates([
        (value: BeaconEvaluationValue.zero, reasonTagsCsv: 'x,y'),
        (value: BeaconEvaluationValue.zero, reasonTagsCsv: 'y,z'),
      ]);
      expect(agg.topReasonTags.first, 'y');
      expect(agg.topReasonTags.toSet(), {'x', 'y', 'z'});
    });
  });

  group('evaluationRoleSummaryLine', () {
    test('empty when no role', () {
      expect(evaluationRoleSummaryLine(null, 'positive'), '');
    });

    test('maps role and tone', () {
      expect(
        evaluationRoleSummaryLine(EvaluationParticipantRole.author, 'positive'),
        'As Author: mostly positive',
      );
      expect(
        evaluationRoleSummaryLine(EvaluationParticipantRole.committer, 'negative'),
        'As Committer: mostly negative',
      );
      expect(
        evaluationRoleSummaryLine(EvaluationParticipantRole.forwarder, 'mixed'),
        'As Forwarder: mixed',
      );
    });
  });

  group('buildEvaluationSummaryGraphqlPayload', () {
    test('wrong beacon state', () {
      final m = buildEvaluationSummaryGraphqlPayload(
        beaconState: 5,
        distinctEvaluatorCount: 10,
        rows: [
          (value: BeaconEvaluationValue.pos1, reasonTagsCsv: ''),
        ],
        viewerRole: EvaluationParticipantRole.author,
      );
      expect(m['suppressed'], isTrue);
      expect(m['tone'], 'mixed');
      expect(m['message'], '');
    });

    test('empty rows', () {
      final m = buildEvaluationSummaryGraphqlPayload(
        beaconState: 6,
        distinctEvaluatorCount: 3,
        rows: [],
        viewerRole: null,
      );
      expect(m['suppressed'], isTrue);
      expect(m['message'], 'No feedback');
    });

    test('privacy when fewer than 3 evaluators', () {
      final m = buildEvaluationSummaryGraphqlPayload(
        beaconState: 6,
        distinctEvaluatorCount: 2,
        rows: [
          (value: BeaconEvaluationValue.pos2, reasonTagsCsv: ''),
        ],
        viewerRole: EvaluationParticipantRole.committer,
      );
      expect(m['suppressed'], isTrue);
      expect(m['tone'], 'positive');
      expect(
        m['message'],
        'Feedback in this beacon (details limited for privacy)',
      );
    });

    test('full detail when enough evaluators', () {
      final m = buildEvaluationSummaryGraphqlPayload(
        beaconState: 6,
        distinctEvaluatorCount: 3,
        rows: [
          (value: BeaconEvaluationValue.pos1, reasonTagsCsv: 't1'),
          (value: BeaconEvaluationValue.pos1, reasonTagsCsv: 't1,t2'),
        ],
        viewerRole: EvaluationParticipantRole.author,
      );
      expect(m['suppressed'], isFalse);
      expect(m['tone'], 'positive');
      expect(m['topReasonTags'], ['t1', 't2']);
      expect(m['roleSummaryLine'], 'As Author: mostly positive');
      expect(m['pos1'], 2);
    });
  });
}
