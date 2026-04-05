import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_participant_role.dart';

/// Row shape for summary aggregation (no Drift types).
typedef SummaryEvaluationRowInput = ({int value, String reasonTagsCsv});

String evaluationToneFromValues(Iterable<int> values) {
  var score = 0;
  for (final v in values) {
    score += switch (v) {
      BeaconEvaluationValue.neg2 => -2,
      BeaconEvaluationValue.neg1 => -1,
      BeaconEvaluationValue.zero => 0,
      BeaconEvaluationValue.pos1 => 1,
      BeaconEvaluationValue.pos2 => 2,
      _ => 0,
    };
  }
  if (score > 0) {
    return 'positive';
  }
  if (score < 0) {
    return 'negative';
  }
  return 'mixed';
}

final class EvaluationSummaryAggregates {
  const EvaluationSummaryAggregates({
    required this.neg2,
    required this.neg1,
    required this.zero,
    required this.pos1,
    required this.pos2,
    required this.topReasonTags,
  });

  final int neg2;
  final int neg1;
  final int zero;
  final int pos1;
  final int pos2;
  final List<String> topReasonTags;
}

EvaluationSummaryAggregates evaluationSummaryAggregates(
  Iterable<SummaryEvaluationRowInput> rows,
) {
  var neg2 = 0;
  var neg1 = 0;
  var zero = 0;
  var pos1 = 0;
  var pos2 = 0;
  final tagCounts = <String, int>{};
  for (final r in rows) {
    switch (r.value) {
      case BeaconEvaluationValue.neg2:
        neg2++;
      case BeaconEvaluationValue.neg1:
        neg1++;
      case BeaconEvaluationValue.zero:
        zero++;
      case BeaconEvaluationValue.pos1:
        pos1++;
      case BeaconEvaluationValue.pos2:
        pos2++;
      default:
        break;
    }
    for (final t in r.reasonTagsCsv.split(',')) {
      if (t.isEmpty) {
        continue;
      }
      tagCounts[t] = (tagCounts[t] ?? 0) + 1;
    }
  }
  final topTags = tagCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return EvaluationSummaryAggregates(
    neg2: neg2,
    neg1: neg1,
    zero: zero,
    pos1: pos1,
    pos2: pos2,
    topReasonTags: topTags.take(5).map((e) => e.key).toList(),
  );
}

String evaluationRoleSummaryLine(
  EvaluationParticipantRole? role,
  String tone,
) {
  if (role == null) {
    return '';
  }
  final label = switch (role) {
    EvaluationParticipantRole.author => 'Author',
    EvaluationParticipantRole.committer => 'Committer',
    EvaluationParticipantRole.forwarder => 'Forwarder',
  };
  final toneWord = switch (tone) {
    'positive' => 'mostly positive',
    'negative' => 'mostly negative',
    _ => 'mixed',
  };
  return 'As $label: $toneWord';
}

/// GraphQL-shaped map for the evaluation summary resolver (unchanged keys).
Map<String, dynamic> buildEvaluationSummaryGraphqlPayload({
  required int beaconState,
  required int distinctEvaluatorCount,
  required List<SummaryEvaluationRowInput> rows,
  required EvaluationParticipantRole? viewerRole,
}) {
  if (beaconState != 6) {
    return {
      'suppressed': true,
      'tone': 'mixed',
      'message': '',
      'topReasonTags': <String>[],
      'roleSummaryLine': '',
    };
  }
  if (rows.isEmpty) {
    return {
      'suppressed': true,
      'tone': 'mixed',
      'message': 'No feedback',
      'topReasonTags': <String>[],
      'roleSummaryLine': '',
    };
  }
  final tone = evaluationToneFromValues(rows.map((r) => r.value));
  if (distinctEvaluatorCount < 3) {
    return {
      'suppressed': true,
      'tone': tone,
      'message': 'Feedback in this beacon (details limited for privacy)',
      'topReasonTags': <String>[],
      'roleSummaryLine': '',
    };
  }
  final agg = evaluationSummaryAggregates(rows);
  return {
    'suppressed': false,
    'tone': tone,
    'message': '',
    'topReasonTags': agg.topReasonTags,
    'neg2': agg.neg2,
    'neg1': agg.neg1,
    'zero': agg.zero,
    'pos1': agg.pos1,
    'pos2': agg.pos2,
    'roleSummaryLine': evaluationRoleSummaryLine(viewerRole, tone),
  };
}
