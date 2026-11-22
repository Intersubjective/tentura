/// Result of accepting an invitation with an existing account.
enum InviteAcceptance {
  accepted,
  requestLapsed,
  notClaimed;

  static InviteAcceptance fromClaim({required bool claimed}) =>
      claimed ? accepted : notClaimed;

  bool get isConsumed => this != notClaimed;
}
