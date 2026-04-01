import 'evaluation_participant_role.dart';

/// Phase 1: reason tag keys per role; validated on submit.
abstract final class EvaluationReasonTags {
  static const authorPositive = <String>[
    'clear_request',
    'fair_closure',
    'useful_updates',
    'coordinated_well',
  ];

  static const authorNegative = <String>[
    'unclear_request',
    'poor_updates',
    'closed_unfairly',
    'hard_to_coordinate',
  ];

  static const committerPositive = <String>[
    'delivered_as_promised',
    'very_useful',
    'communicated_honestly',
    'above_expectation',
  ];

  static const committerNegative = <String>[
    'did_not_follow_through',
    'overpromised',
    'created_extra_work',
    'poor_communication',
  ];

  static const forwarderPositive = <String>[
    'reached_right_person',
    'forwarded_quickly',
    'useful_routing_note',
    'crucial_bridge',
  ];

  static const forwarderNegative = <String>[
    'sent_to_wrong_people',
    'created_noise',
    'forwarded_too_late',
    'misleading_note',
  ];

  static Set<String> allowedForRoleAndSign(
    EvaluationParticipantRole role, {
    required bool isNegative,
  }) {
    switch (role) {
      case EvaluationParticipantRole.author:
        return isNegative
            ? authorNegative.toSet()
            : authorPositive.toSet();
      case EvaluationParticipantRole.committer:
        return isNegative
            ? committerNegative.toSet()
            : committerPositive.toSet();
      case EvaluationParticipantRole.forwarder:
        return isNegative
            ? forwarderNegative.toSet()
            : forwarderPositive.toSet();
    }
  }

  /// For ZERO / optional tags: any tag from either list for that role.
  static Set<String> allowedUnionForRole(EvaluationParticipantRole role) =>
      {...switch (role) {
        EvaluationParticipantRole.author => [...authorPositive, ...authorNegative],
        EvaluationParticipantRole.committer => [
            ...committerPositive,
            ...committerNegative,
          ],
        EvaluationParticipantRole.forwarder => [
            ...forwarderPositive,
            ...forwarderNegative,
          ],
      }};
}
