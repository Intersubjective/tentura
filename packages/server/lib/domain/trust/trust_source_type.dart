enum TrustSourceType {
  userVote('user_vote'),
  finalizedRequestEvaluation('finalized_request_evaluation'),
  propagatedAuthorEvaluatedCommitment(
    'propagated_author_evaluated_commitment',
  ),
  negativeCommitmentRouteNoEffect('negative_commitment_route_no_effect'),
  unsuccessfulRequestForward('unsuccessful_request_forward');

  const TrustSourceType(this.key);

  final String key;
}
