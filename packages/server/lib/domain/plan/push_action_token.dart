import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/env.dart';

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

/// Short-lived signed token carried by a plan push, so a notification button
/// can act without opening the app or holding a session.
///
/// An EdDSA JWT under the server keys, bound to this server (issuer) and to
/// its own audience. It deliberately has **no `sub`**: an access-token parser
/// requires one, so this token can never be replayed as a session, and an
/// access token (no audience, no `pacc`) never passes [verify].
@singleton
class PushActionToken {
  const PushActionToken(this._env);

  final Env _env;

  /// Upper bound of a token's life (plan §5.9: `exp ≤ 24 h`).
  static const maxTtl = Duration(hours: 24);

  static const _purpose = 'push_action';
  static const _audience = 'tentura:push_action';

  String sign(PushActionClaims claims, {Duration ttl = maxTtl}) =>
      JWT(
        {
          'purpose': _purpose,
          'pacc': claims.accountId,
          'act': claims.action.name,
          'bid': claims.beaconId,
          'sid': ?claims.stepId,
          'seq': ?claims.seq,
        },
        issuer: _env.publicOrigin,
        audience: Audience.one(_audience),
      ).sign(
        _env.privateKey,
        algorithm: JWTAlgorithm.EdDSA,
        expiresIn: ttl > maxTtl || ttl.isNegative ? maxTtl : ttl,
      );

  /// The claims when [token] is genuine, unexpired and well-formed; else
  /// null.
  PushActionClaims? verify(String token) {
    if (token.isEmpty) return null;
    final Map<String, dynamic> map;
    try {
      final payload = JWT
          .verify(
            token,
            _env.publicKey,
            issuer: _env.publicOrigin,
            audience: Audience.one(_audience),
          )
          .payload;
      if (payload is! Map<String, dynamic>) return null;
      map = payload;
    } catch (_) {
      // Bad signature, expired, wrong issuer / audience or not a JWT.
      return null;
    }
    // A token without an expiry would live forever.
    if (map['purpose'] != _purpose || map['exp'] is! num) return null;
    final accountId = map['pacc'];
    final beaconId = map['bid'];
    final action = PushAction.fromWire(map['act']);
    if (accountId is! String || accountId.isEmpty) return null;
    if (beaconId is! String || beaconId.isEmpty || action == null) return null;
    final stepId = map['sid'];
    final seq = map['seq'];
    switch (action) {
      case PushAction.done when stepId is! String || stepId.isEmpty:
        return null;
      case PushAction.ack when seq is! int || seq < 0:
        return null;
      case _:
    }
    return PushActionClaims(
      accountId: accountId,
      action: action,
      beaconId: beaconId,
      stepId: stepId is String ? stepId : null,
      seq: seq is int ? seq : null,
    );
  }
}
