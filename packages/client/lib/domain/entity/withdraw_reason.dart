/// Withdraw reason tag keys (server `kAllowedWithdrawReasonKeys`).
enum WithdrawReason {
  cannotDoIt,
  timing,
  wrongFit,
  someoneElse,
  other;

  String get wireKey => switch (this) {
        WithdrawReason.cannotDoIt => 'cannot_do_it',
        WithdrawReason.timing => 'timing',
        WithdrawReason.wrongFit => 'wrong_fit',
        WithdrawReason.someoneElse => 'someone_else',
        WithdrawReason.other => 'other',
      };
}
