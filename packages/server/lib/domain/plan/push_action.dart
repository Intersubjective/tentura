/// Request plan («либретто», #220): push notification button actions
/// (plan §5.9) and the claims a signed action token carries.
library;

/// What a push notification button does (plan §5.9, P1..P3).
enum PushAction {
  /// «Готово»: tick the step.
  done,

  /// «Понятно»: confirm plan changes up to a revision.
  ack;

  static PushAction? fromWire(Object? v) {
    for (final a in values) {
      if (a.name == v) return a;
    }
    return null;
  }
}

/// The verified content of a push action token.
final class PushActionClaims {
  const PushActionClaims({
    required this.accountId,
    required this.action,
    required this.beaconId,
    this.stepId,
    this.seq,
  });

  final String accountId;
  final PushAction action;
  final String beaconId;

  /// The step to tick ([PushAction.done]).
  final String? stepId;

  /// The plan revision «Понятно» confirms up to ([PushAction.ack]).
  final int? seq;
}
