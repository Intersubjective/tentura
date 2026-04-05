/// Uncommit reason tag keys (server `kAllowedUncommitReasonKeys`).
enum UncommitReason {
  cannotDoIt,
  timing,
  wrongFit,
  someoneElse,
  other;

  String get wireKey => switch (this) {
        UncommitReason.cannotDoIt => 'cannot_do_it',
        UncommitReason.timing => 'timing',
        UncommitReason.wrongFit => 'wrong_fit',
        UncommitReason.someoneElse => 'someone_else',
        UncommitReason.other => 'other',
      };
}
