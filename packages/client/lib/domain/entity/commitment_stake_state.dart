/// Projection of `beacon_help_offer.stake_state` (§2.5); ordinal matches DB values.
enum CommitmentStakeState {
  none,
  offered,
  acknowledged,
  softened,
  exited,
  released,
  ;

  static CommitmentStakeState fromInt(int? value) {
    if (value == null) return CommitmentStakeState.none;
    if (value < 0 || value >= CommitmentStakeState.values.length) {
      return CommitmentStakeState.none;
    }
    return CommitmentStakeState.values[value];
  }
}
