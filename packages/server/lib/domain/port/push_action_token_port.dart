import 'package:tentura_server/domain/plan/push_action.dart';

/// Short-lived signed token carried by a plan push, so a notification button
/// can act without opening the app or holding a session (plan §5.9).
abstract interface class PushActionTokenPort {
  /// Upper bound of a token's life (plan §5.9: `exp ≤ 24 h`).
  static const maxTtl = Duration(hours: 24);

  /// Signs [claims]; [ttl] is capped at [maxTtl].
  String sign(PushActionClaims claims, {Duration ttl = maxTtl});

  /// The claims when [token] is genuine, unexpired and well-formed; else
  /// null.
  PushActionClaims? verify(String token);
}
